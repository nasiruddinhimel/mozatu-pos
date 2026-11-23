import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITESUPABASEURL;
const key = import.meta.env.VITESUPABASEANONKEY;
export const supabase = url && key ? createClient(url, key) : null;
