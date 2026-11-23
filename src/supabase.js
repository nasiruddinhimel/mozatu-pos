import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASEURL;
const key = import.meta.env.VITE_SUPABASEANONKEY;
export const supabase = url && key ? createClient(url, key) : null;
