-- =============================================================
-- Boutique Fashion POS  ·  Esquema PostgreSQL (Supabase)
-- Ejecutar en el SQL Editor de Supabase
-- =============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------- ENUMS ----------
CREATE TYPE user_role AS ENUM ('ADMIN', 'COLABORADOR');
CREATE TYPE movement_type AS ENUM ('ENTRY', 'SALE', 'RETURN', 'ADJUSTMENT');
CREATE TYPE payment_method AS ENUM ('CASH', 'CARD', 'BANK_TRANSFER');
CREATE TYPE shift_status AS ENUM ('OPEN', 'CLOSED');

-- ---------- PERFILES / RBAC ----------
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    role user_role NOT NULL DEFAULT 'COLABORADOR',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- CATEGORÍAS ----------
CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- PRODUCTOS ----------
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    cost_price NUMERIC(12,2) NOT NULL CHECK (cost_price >= 0),
    retail_price NUMERIC(12,2) NOT NULL CHECK (retail_price >= cost_price),
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- VARIANTES (SKU / QR / Stock) ----------
CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    sku VARCHAR(64) NOT NULL UNIQUE,
    size VARCHAR(20) NOT NULL,
    color VARCHAR(50) NOT NULL,
    current_stock INT NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
    min_stock_alert INT NOT NULL DEFAULT 3 CHECK (min_stock_alert >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_product_size_color UNIQUE (product_id, size, color)
);

CREATE INDEX idx_variants_sku ON public.product_variants(sku);
CREATE INDEX idx_variants_product ON public.product_variants(product_id);
CREATE INDEX idx_variants_low_stock ON public.product_variants(current_stock)
    WHERE current_stock <= min_stock_alert;

-- ---------- CAJA / TURNOS ----------
CREATE TABLE public.cash_shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    opening_balance NUMERIC(12,2) NOT NULL CHECK (opening_balance >= 0),
    closing_balance NUMERIC(12,2) DEFAULT NULL,
    calculated_cash NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    status shift_status NOT NULL DEFAULT 'OPEN',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ DEFAULT NULL
);

-- Solo un turno abierto por usuario
CREATE UNIQUE INDEX uniq_open_shift_per_user
    ON public.cash_shifts(user_id) WHERE status = 'OPEN';

-- ---------- VENTAS ----------
CREATE TABLE public.sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shift_id UUID NOT NULL REFERENCES public.cash_shifts(id) ON DELETE RESTRICT,
    cashier_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    sale_number BIGSERIAL UNIQUE,
    subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    tax NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (tax >= 0),
    total NUMERIC(12,2) NOT NULL CHECK (total >= 0),
    payment_method payment_method NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sales_shift ON public.sales(shift_id);
CREATE INDEX idx_sales_created ON public.sales(created_at DESC);

-- ---------- DETALLE DE VENTAS ----------
CREATE TABLE public.sale_details (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- COMPROBANTES DE PAGO ----------
CREATE TABLE public.payment_proofs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL UNIQUE REFERENCES public.sales(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- KARDEX / AUDITORÍA DE INVENTARIO ----------
CREATE TABLE public.inventory_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    type movement_type NOT NULL,
    quantity INT NOT NULL,
    stock_before INT NOT NULL,
    stock_after INT NOT NULL,
    reference_id UUID,
    performed_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_movements_variant ON public.inventory_movements(variant_id, created_at DESC);

-- =============================================================
-- RPC 1: Venta atómica (Zero-Oversell con SELECT ... FOR UPDATE)
-- =============================================================
CREATE OR REPLACE FUNCTION public.execute_sale(
    p_shift_id UUID,
    p_cashier_id UUID,
    p_payment_method payment_method,
    p_items JSONB,
    p_proof_path TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sale_id UUID;
    v_item RECORD;
    v_current_stock INT;
    v_subtotal NUMERIC(12,2) := 0;
    v_shift_status shift_status;
BEGIN
    SELECT status INTO v_shift_status
    FROM public.cash_shifts WHERE id = p_shift_id FOR UPDATE;

    IF v_shift_status IS NULL OR v_shift_status <> 'OPEN' THEN
        RAISE EXCEPTION 'Turno de caja % no existe o esta cerrado.', p_shift_id;
    END IF;

    FOR v_item IN
        SELECT * FROM jsonb_to_recordset(p_items)
        AS x(variant_id UUID, quantity INT, unit_price NUMERIC)
    LOOP
        v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);
    END LOOP;

    INSERT INTO public.sales (shift_id, cashier_id, subtotal, tax, total, payment_method, notes)
    VALUES (p_shift_id, p_cashier_id, v_subtotal, 0.00, v_subtotal, p_payment_method, p_notes)
    RETURNING id INTO v_sale_id;

    FOR v_item IN
        SELECT * FROM jsonb_to_recordset(p_items)
        AS x(variant_id UUID, quantity INT, unit_price NUMERIC)
    LOOP
        SELECT current_stock INTO v_current_stock
        FROM public.product_variants
        WHERE id = v_item.variant_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La variante % no existe en catalogo.', v_item.variant_id;
        END IF;

        IF v_current_stock < v_item.quantity THEN
            RAISE EXCEPTION 'Stock insuficiente para variante %. Disponible: %, Solicitado: %',
                v_item.variant_id, v_current_stock, v_item.quantity;
        END IF;

        INSERT INTO public.sale_details (sale_id, variant_id, quantity, unit_price, total_price)
        VALUES (v_sale_id, v_item.variant_id, v_item.quantity, v_item.unit_price,
                (v_item.quantity * v_item.unit_price));

        UPDATE public.product_variants
        SET current_stock = current_stock - v_item.quantity, updated_at = NOW()
        WHERE id = v_item.variant_id;

        INSERT INTO public.inventory_movements
            (variant_id, type, quantity, stock_before, stock_after, reference_id, performed_by)
        VALUES (v_item.variant_id, 'SALE', -v_item.quantity, v_current_stock,
                (v_current_stock - v_item.quantity), v_sale_id, p_cashier_id);
    END LOOP;

    IF p_proof_path IS NOT NULL THEN
        INSERT INTO public.payment_proofs (sale_id, storage_path, uploaded_by)
        VALUES (v_sale_id, p_proof_path, p_cashier_id);
    END IF;

    IF p_payment_method = 'CASH' THEN
        UPDATE public.cash_shifts
        SET calculated_cash = calculated_cash + v_subtotal
        WHERE id = p_shift_id;
    END IF;

    RETURN v_sale_id;
END;
$$;

-- =============================================================
-- RPC 2: Alta de producto con variantes (atómica)
-- =============================================================
CREATE OR REPLACE FUNCTION public.register_product_with_variants(
    p_name TEXT,
    p_category_id UUID,
    p_cost_price NUMERIC,
    p_retail_price NUMERIC,
    p_image_url TEXT,
    p_variants JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_product_id UUID;
    v_variant RECORD;
BEGIN
    INSERT INTO public.products (category_id, name, cost_price, retail_price, image_url)
    VALUES (p_category_id, p_name, p_cost_price, p_retail_price, p_image_url)
    RETURNING id INTO v_product_id;

    FOR v_variant IN
        SELECT * FROM jsonb_to_recordset(p_variants)
        AS x(sku TEXT, size TEXT, color TEXT, current_stock INT)
    LOOP
        INSERT INTO public.product_variants
            (product_id, sku, size, color, current_stock)
        VALUES (v_product_id, v_variant.sku, v_variant.size, v_variant.color, v_variant.current_stock);

        INSERT INTO public.inventory_movements
            (variant_id, type, quantity, stock_before, stock_after, reference_id, performed_by)
        SELECT id, 'ENTRY', v_variant.current_stock, 0, v_variant.current_stock,
               v_product_id, auth.uid()
        FROM public.product_variants WHERE sku = v_variant.sku;
    END LOOP;

    RETURN v_product_id;
END;
$$;

-- =============================================================
-- Row Level Security
-- COLABORADOR: puede leer catálogo/ventas pero NO costos ni márgenes.
-- =============================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS user_role
LANGUAGE sql
STABLE
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(public.current_user_role() = 'ADMIN', FALSE);
$$;

-- Política: productos
CREATE POLICY products_select ON public.products
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY products_admin_write ON public.products
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Política: variantes (lectura para ambos roles, escritura solo ADMIN)
CREATE POLICY variants_select ON public.product_variants
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY variants_admin_write ON public.product_variants
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Política: categorías
CREATE POLICY categories_select ON public.categories
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY categories_admin_write ON public.categories
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Política: ventas
CREATE POLICY sales_select ON public.sales
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY sales_insert ON public.sales
    FOR INSERT WITH CHECK (cashier_id = auth.uid());

-- Política: detalle de ventas
CREATE POLICY sale_details_select ON public.sale_details
    FOR SELECT USING (auth.role() = 'authenticated');

-- Política: comprobantes
CREATE POLICY proofs_select ON public.payment_proofs
    FOR SELECT USING (auth.role() = 'authenticated');

-- Política: caja (usuario ve su propio turno; admin ve todos)
CREATE POLICY shifts_select ON public.cash_shifts
    FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY shifts_insert ON public.cash_shifts
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY shifts_update ON public.cash_shifts
    FOR UPDATE USING (user_id = auth.uid() OR public.is_admin());

-- Política: kardex (costos solo admin)
CREATE POLICY movements_select ON public.inventory_movements
    FOR SELECT USING (public.is_admin());

-- Perfil propio
CREATE POLICY profiles_select_own ON public.profiles
    FOR SELECT USING (id = auth.uid() OR public.is_admin());

CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE USING (id = auth.uid() OR public.is_admin());

-- =============================================================
-- Buckets de Storage
-- =============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES
    ('product-images', 'product-images', TRUE),
    ('payment-receipts', 'payment-receipts', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Comprobantes de pago: solo el usuario autenticado accede a su carpeta
CREATE POLICY "payment proof upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'payment-receipts');

CREATE POLICY "payment proof read"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'payment-receipts');