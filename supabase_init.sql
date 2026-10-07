-- ===== 1. TABLAS =====
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null,
  role text not null default 'COLABORADOR' check (role in ('ADMIN','COLABORADOR')),
  is_active boolean not null default true
);

create table public.categories (
  id text primary key,
  name text not null,
  description text
);

create table public.products (
  id text primary key,
  category_id text not null references public.categories(id),
  name text not null,
  description text,
  cost_price numeric not null,
  retail_price numeric not null,
  image_url text,
  is_active boolean not null default true
);

create table public.product_variants (
  id text primary key,
  product_id text not null references public.products(id),
  sku text not null unique,
  size text not null,
  color text not null,
  current_stock integer not null default 0,
  min_stock_alert integer not null default 3
);

create table public.cash_shifts (
  id text primary key default ('shift-' || to_char(now(),'YYYYMMDDHH24MISSMS')),
  user_id text not null,
  opening_balance numeric not null default 0,
  closing_balance numeric,
  calculated_cash numeric not null default 0,
  status text not null check (status in ('OPEN','CLOSED')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  shift_id text not null references public.cash_shifts(id),
  cashier_id text not null,
  subtotal numeric not null default 0,
  tax numeric not null default 0,
  total numeric not null default 0,
  payment_method text not null check (payment_method in ('CASH','CARD','TRANSFER','MIXED')),
  notes text,
  proof_path text,
  created_at timestamptz not null default now()
);

create table public.sale_details (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  variant_id text not null references public.product_variants(id),
  quantity integer not null,
  unit_price numeric not null
);

create index on public.products(category_id);
create index on public.product_variants(product_id);
create index on public.sales(shift_id);
create index on public.sale_details(sale_id);

-- ===== 2. DATOS SEMILLA =====
insert into public.categories (id, name, description) values
  ('cat-1','Camisas','Camisas de vestir y casuales'),
  ('cat-2','Pantalones','Jeans, pantalones chinos y bermudas'),
  ('cat-3','Ropa Interior','Calcetines y boxer shorts'),
  ('cat-4','Chaquetas','Abrigos y chaquetas impermeables');

insert into public.products (id, category_id, name, cost_price, retail_price, is_active) values
  ('p-1','cat-1','Camisa Oxford Classic Fit',15.00,35.00,true),
  ('p-2','cat-2','Jeans Slim Fit Denim',20.00,49.99,true);

insert into public.product_variants (id, product_id, sku, size, color, current_stock, min_stock_alert) values
  ('v-1','p-1','OXF-S-BLUE-1234','S','Azul Celeste',12,3),
  ('v-2','p-1','OXF-M-BLUE-1234','M','Azul Celeste',8,3),
  ('v-3','p-1','OXF-L-BLUE-1234','L','Azul Celeste',2,3),
  ('v-4','p-2','SLM-32-INDG-5678','32','Indigo',15,3),
  ('v-5','p-2','SLM-34-INDG-5678','34','Indigo',0,3);

-- ===== 3. RPC: registrar producto + variantes =====
create or replace function public.register_product_with_variants(
  p_name text, p_category_id text, p_cost_price numeric,
  p_retail_price numeric, p_image_url text default null,
  p_variants jsonb default '[]'::jsonb
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_product_id text := 'p-' || gen_random_uuid()::text;
  v_item jsonb;
begin
  insert into products (id, category_id, name, cost_price, retail_price, image_url)
  values (v_product_id, p_category_id, p_name, p_cost_price, p_retail_price, p_image_url);

  for v_item in select * from jsonb_array_elements(p_variants) loop
    insert into product_variants (id, product_id, sku, size, color, current_stock, min_stock_alert)
    values ('v-' || gen_random_uuid()::text, v_product_id,
            v_item->>'sku', v_item->>'size', v_item->>'color',
            coalesce((v_item->>'current_stock')::int, 0),
            coalesce((v_item->>'min_stock_alert')::int, 3));
  end loop;
  return v_product_id;
end $$;

-- ===== 4. RPC: venta ACID =====
create or replace function public.execute_sale(
  p_shift_id text, p_cashier_id text, p_payment_method text,
  p_items jsonb, p_proof_path text default null, p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_sale_id uuid;
  v_total numeric := 0;
  v_item jsonb;
  v_variant record;
  v_qty int;
  v_price numeric;
begin
  perform 1 from cash_shifts where id = p_shift_id and status = 'OPEN' for update;
  if not found then
    raise exception 'El turno de caja especificado no existe o se encuentra cerrado.';
  end if;

  insert into sales (shift_id, cashier_id, payment_method, proof_path, notes)
  values (p_shift_id, p_cashier_id, p_payment_method, p_proof_path, p_notes)
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::int;
    v_price := (v_item->>'unit_price')::numeric;

    select * into v_variant from product_variants
    where id = v_item->>'variant_id' for update;
    if not found then
      raise exception 'La variante de producto no existe en el catálogo.';
    end if;
    if v_variant.current_stock < v_qty then
      raise exception 'Stock insuficiente para la variante: %. Disponible: %',
        v_variant.sku, v_variant.current_stock;
    end if;

    update product_variants set current_stock = current_stock - v_qty where id = v_variant.id;
    insert into sale_details (sale_id, variant_id, quantity, unit_price)
    values (v_sale_id, v_variant.id, v_qty, v_price);
    v_total := v_total + v_qty * v_price;
  end loop;

  update sales set subtotal = v_total, total = v_total where id = v_sale_id;
  if p_payment_method = 'CASH' then
    update cash_shifts set calculated_cash = calculated_cash + v_total where id = p_shift_id;
  end if;
  return v_sale_id;
end $$;

-- ===== 5. PERMISOS (RLS) =====
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.cash_shifts enable row level security;
alter table public.sales enable row level security;
alter table public.sale_details enable row level security;

do $$
declare t text;
begin
  foreach t in array array['profiles','categories','products','product_variants','cash_shifts','sales','sale_details']
  loop
    execute format('create policy "acceso total autenticado" on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- ===== 6. ALMACENAMIENTO =====
insert into storage.buckets (id, name, public)
values ('product-images','product-images', true), ('payment-receipts','payment-receipts', false)
on conflict (id) do nothing;

drop policy if exists "subir imagenes" on storage.objects;
create policy "subir imagenes" on storage.objects for insert to authenticated
  with check (bucket_id in ('product-images','payment-receipts'));

drop policy if exists "leer imagenes" on storage.objects;
create policy "leer imagenes" on storage.objects for select to authenticated
  using (bucket_id in ('product-images','payment-receipts'));
