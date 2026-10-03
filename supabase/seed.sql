-- Datos iniciales mínimos
INSERT INTO public.categories (name, description) VALUES
  ('Camisas', 'Camisas de vestir y casuales'),
  ('Pantalones', 'Jeans, chinos y bermudas'),
  ('Ropa Interior', 'Calcetines, boxer shorts y ropa interior'),
  ('Chaquetas', 'Abrigos, chaquetas e impermeables'),
  ('Zapatos', 'Calzado en general')
ON CONFLICT (name) DO NOTHING;

-- Crear el perfil ADMIN manualmente tras registrar el usuario en Supabase Auth:
-- INSERT INTO public.profiles (id, email, full_name, role)
-- VALUES ('<auth-user-uuid>', 'admin@boutique.com', 'Administrador', 'ADMIN');