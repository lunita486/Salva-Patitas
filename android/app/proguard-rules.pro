# Reglas propias del proyecto. Firebase, geolocator, image_picker, etc. ya
# traen sus propias reglas de consumo empaquetadas en sus .aar (AGP las
# aplica solas) — esto queda casi vacío a propósito, no hace falta
# reinventar lo que cada librería ya declara por su cuenta.

# google_sign_in usa Credential Manager (reflection/AIDL de Play Services) —
# evita que R8 lo achique de más si algún día deja de traer su propia regla.
-keep class com.google.android.gms.auth.api.credentials.** { *; }
