# Boutique POS · Flutter

Aplicación móvil (Flutter) para **inventario y punto de venta** de una tienda de ropa.
Escaneo de QR, control de stock en tiempo real, comprobantes de pago, recibos PDF y arqueo de caja.

## Estado actual

La app arranca en **modo demo** (base de datos en memoria) si no se pasan credenciales de Supabase,
de modo que se puede probar todo el flujo sin backend.

## Ejecutar

```bash
flutter pub get
flutter run
```

### Conectar Supabase (modo producción)

```bash
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=sbp_xxx
```

1. Ejecuta `supabase/schema.sql` en el SQL Editor (tablas, RPCs, RLS y buckets).
2. Ejecuta `supabase/seed.sql` (categorías).
3. Crea los usuarios en Supabase Auth (o usa **Regístrate** dentro de la app).
   En el primer ingreso de un usuario nuevo se crea automáticamente su fila en
   `public.profiles` con rol `COLABORADOR`; cambia el rol a `ADMIN` desde el SQL
   Editor si necesita acceso a costos/márgenes.

### Por qué antes fallaba "cargar categorías"

Las políticas RLS del proyecto exigen `auth.role() = 'authenticated'`, pero la app
**no tenía pantalla de login**: todas las consultas se hacían con el rol `anon`,
así que PostgREST respondía `401/42501` (o 0 filas) y la UI pintaba el error crudo.

Correcciones aplicadas:

| Defecto | Corrección |
| --- | --- |
| Sin autenticación → RLS bloqueaba todo | Pantalla de login/registro real + `SessionController` que escucha `onAuthStateChange` |
| Error crudo de PostgREST en pantalla | `AppException` con mensajes accionables por código (`42P01`, `42501`, `401`, `23505`, …) |
| Fallo silencioso al inicializar Supabase | `SupabaseConfig.initializationError` + banner `_BackendWarning` con botón **Reintentar** |
| Desplegable de categoría sin opciones ni explicación | Estado vacío explícito y botón **Reintentar** que invalida `categoriesProvider` |
| `DropdownButtonFormField` con valor fuera de la lista | Se valida `initialValue` contra los `items` para evitar el assert *"exactly one item"* |
| `RenderFlex overflowed` en pantallas ≤ 320 dp | Fila "Matriz de variantes" convertida a `Wrap` |

## SKUs de prueba (modo demo)

| SKU | Producto | Talla | Stock |
| --- | --- | --- | --- |
| `OXF-S-BLUE-1234` | Camisa Oxford Classic Fit | S | 12 |
| `OXF-M-BLUE-1234` | Camisa Oxford Classic Fit | M | 8 |
| `OXF-L-BLUE-1234` | Camisa Oxford Classic Fit | L | 2 (crítico) |
| `SLM-32-INDG-5678` | Jeans Slim Fit Denim | 32 | 15 |
| `SLM-34-INDG-5678` | Jeans Slim Fit Denim | 34 | 0 (agotado) |

Si la cámara no está disponible (emulador/simulador), usa el campo de entrada manual
superior para digitar el SKU.

## Estructura

```
lib/
├── core/
│   ├── config/supabase_config.dart     # Config, modo demo y verificación del backend
│   ├── errors/app_exception.dart       # Excepciones tipadas con mensajes accionables
│   ├── router/home_shell.dart          # Shell con tabs y RBAC
│   └── theme/app_theme.dart            # Material 3
├── features/
│   ├── auth/                           # Login real (Supabase Auth) + perfil/rol
│   ├── inventory/                      # Producto, variante, alta de mercancía, catálogo
│   ├── pos/                            # Escáner QR, carrito, checkout, caja
│   └── receipt/                        # PDF térmico 80mm + share_plus
└── app.dart / main.dart
```

## Módulos

- **POS**: `mobile_scanner` + `DraggableScrollableSheet` para operar con una mano,
  badges de stock (rojo/naranja/verde) y validación de límites por variante.
- **Checkout**: método de pago obligatorio (Efectivo / Datáfono / Transferencia),
  comprobante foto obligatorio para medios electrónicos, imagen comprimida localmente.
- **Venta atómica**: `PosRepository.processSaleTransaction` → RPC `execute_sale`
  con `SELECT ... FOR UPDATE` (Zero Oversell) y kárdex automático.
- **Recibo**: PDF en papel continuo de 80 mm con QR de validación, compartible por WhatsApp/Correo.
- **Caja**: apertura con base, métricas en vivo por medio de pago y cierre con
  diferencia (sobrante/faltante).
- **RBAC**: `COLABORADOR` no ve la pestaña de ingreso de mercancía ni costos/márgenes;
  la restricción se repite en las políticas RLS del backend.
- **Ingreso de bodega**: matriz dinámica talla × color, stock inicial, SKU autogenerado
  e impresión de etiquetas QR en A4.

## Calidad

```bash
dart analyze     # sin incidencias
flutter test     # smoke test + regresión de layout + mapeo de errores
```