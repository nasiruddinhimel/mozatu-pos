create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text,
 role text not null default 'owner' check (role in ('owner','manager','cashier')),
 created_at timestamptz not null default now()
);

create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 type text not null check (type in ('raw_material','finished_product')),
 unit text not null,
 selling_price numeric(12,2) not null default 0,
 opening_stock numeric(14,3) not null default 0,
 reorder_level numeric(14,3) not null default 0,
 created_at timestamptz not null default now()
);

create table if not exists public.purchases (
 id uuid primary key default gen_random_uuid(),
 business_date date not null default current_date,
 invoice_no text not null,
 supplier text,
 product_id uuid not null references public.products(id),
 quantity numeric(14,3) not null check(quantity>0),
 unit text not null,
 unit_cost numeric(12,2) not null check(unit_cost>=0),
 total_cost numeric(14,2) generated always as (quantity*unit_cost) stored,
 created_at timestamptz not null default now()
);

create table if not exists public.recipes (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id) on delete cascade,
 raw_material_id uuid not null references public.products(id),
 quantity_per_serving numeric(14,4) not null check(quantity_per_serving>0),
 unit text not null,
 cost_per_unit numeric(12,4) not null default 0,
 created_at timestamptz not null default now(),
 unique(product_id,raw_material_id)
);

create table if not exists public.sales (
 id uuid primary key default gen_random_uuid(),
 business_date date not null default current_date,
 invoice_no text not null,
 product_id uuid not null references public.products(id),
 quantity numeric(14,3) not null check(quantity>0),
 unit_price numeric(12,2) not null check(unit_price>=0),
 discount numeric(12,2) not null default 0,
 net_total numeric(14,2) not null,
 cogs numeric(14,2) not null default 0,
 payment_method text not null default 'Cash',
 created_at timestamptz not null default now()
);

create table if not exists public.expenses (
 id uuid primary key default gen_random_uuid(),
 business_date date not null default current_date,
 category text not null,
 description text,
 amount numeric(14,2) not null check(amount>=0),
 payment_method text not null default 'Cash',
 created_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id),
 movement_type text not null check(movement_type in ('opening','purchase','sale_consumption','production_in','production_out','adjustment')),
 quantity_delta numeric(14,3) not null,
 reference_id uuid,
 note text,
 created_at timestamptz not null default now()
);

-- Purchase transaction: add stock movement and purchase row atomically.
create or replace function public.record_purchase(p_date date,p_invoice text,p_supplier text,p_product uuid,p_qty numeric,p_unit text,p_unit_cost numeric)
returns uuid language plpgsql security invoker as $$
declare v_id uuid;
begin
 if p_qty<=0 or p_unit_cost<0 then raise exception 'Invalid purchase quantity or cost'; end if;
 if not exists(select 1 from public.products where id=p_product and type='raw_material') then raise exception 'Select a raw material'; end if;
 insert into public.purchases(business_date,invoice_no,supplier,product_id,quantity,unit,unit_cost)
 values(p_date,p_invoice,p_supplier,p_product,p_qty,p_unit,p_unit_cost) returning id into v_id;
 insert into public.stock_movements(product_id,movement_type,quantity_delta,reference_id,note)
 values(p_product,'purchase',p_qty,v_id,'Purchase '||p_invoice);
 return v_id;
end $$;

-- Sales RPC applies recipe stock deduction and COGS in the same database transaction.
create or replace function public.record_sale(p_date date,p_invoice text,p_product uuid,p_qty numeric,p_unit_price numeric,p_discount numeric default 0,p_payment text default 'Cash')
returns uuid language plpgsql security invoker as $$
declare v_id uuid; v_cogs numeric(14,2); v_count int;
begin
 if p_qty<=0 or p_unit_price<0 or p_discount<0 then raise exception 'Invalid sale values'; end if;
 if not exists(select 1 from public.products where id=p_product and type='finished_product') then raise exception 'Select a finished product'; end if;
 select count(*),coalesce(sum(r.quantity_per_serving*p_qty*r.cost_per_unit),0)
 into v_count,v_cogs from public.recipes r where r.product_id=p_product;
 if v_count=0 then raise exception 'Set the product recipe before recipe-based sale'; end if;
 if exists(
   select 1 from public.recipes r
   left join (select product_id,sum(quantity_delta) qty from public.stock_movements group by product_id) st on st.product_id=r.raw_material_id
   left join public.products p on p.id=r.raw_material_id
   where r.product_id=p_product and coalesce(p.opening_stock,0)+coalesce(st.qty,0)<r.quantity_per_serving*p_qty
 ) then raise exception 'Insufficient raw material stock'; end if;
 insert into public.sales(business_date,invoice_no,product_id,quantity,unit_price,discount,net_total,cogs,payment_method)
 values(p_date,p_invoice,p_product,p_qty,p_unit_price,p_discount,(p_qty*p_unit_price)-p_discount,v_cogs,p_payment) returning id into v_id;
 insert into public.stock_movements(product_id,movement_type,quantity_delta,reference_id,note)
 select raw_material_id,'sale_consumption',-(quantity_per_serving*p_qty),v_id,'Recipe consumption '||p_invoice
 from public.recipes where product_id=p_product;
 return v_id;
end $$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.purchases enable row level security;
alter table public.recipes enable row level security;
alter table public.sales enable row level security;
alter table public.expenses enable row level security;
alter table public.stock_movements enable row level security;

-- Single-business starter: authenticated users can access business records.
-- Tighten this policy to organization_id-based isolation before adding multiple client businesses.
do $$ declare t text; begin
 foreach t in array array['products','purchases','recipes','sales','expenses','stock_movements'] loop
  execute format('drop policy if exists "authenticated_all_%s" on public.%I',t,t);
  execute format('create policy "authenticated_all_%s" on public.%I for all to authenticated using (true) with check (true)',t,t);
 end loop;
end $$;

drop policy if exists "profile_self" on public.profiles;
create policy "profile_self" on public.profiles for all to authenticated using (id=auth.uid()) with check (id=auth.uid());

create or replace view public.stock_balances as
select p.id as product_id,p.name,p.type,p.unit,p.opening_stock + coalesce(sum(sm.quantity_delta),0) as on_hand,p.reorder_level
from public.products p
left join public.stock_movements sm on sm.product_id=p.id
group by p.id,p.name,p.type,p.unit,p.opening_stock,p.reorder_level;
