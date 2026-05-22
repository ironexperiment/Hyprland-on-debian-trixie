# Compilar Hyprland 0.53 en Debian Trixie

> Guía detallada para compilar e instalar Hyprland 0.53 (enero 2026) en Debian 13 "Trixie"
> usando únicamente el toolchain estándar de la distribución (**GCC 14.2 / libstdc++ 14**).
>
> Probada en: Lenovo IdeaPad 330-15IKB (Intel i3-8130U / 4 GiB RAM / UHD 620),
> Debian 13.5 con GNOME 48 + GDM como display manager.

## Tabla de contenidos
1. [Por qué no se puede instalar desde apt](#1-por-qué-no-se-puede-instalar-desde-apt)
2. [Resumen del problema y la solución](#2-resumen-del-problema-y-la-solución)
3. [Paquetes de Debian necesarios](#3-paquetes-de-debian-necesarios)
4. [Orden de compilación](#4-orden-de-compilación)
5. [Compilar las dependencias from-source](#5-compilar-las-dependencias-from-source)
6. [Parchar hyprwire para libstdc++ 14](#6-parchar-hyprwire-para-libstdc-14)
7. [Parchar Hyprland para GCC 14](#7-parchar-hyprland-para-gcc-14)
8. [Compilar e instalar Hyprland](#8-compilar-e-instalar-hyprland)
9. [Acompañantes recomendados](#9-acompañantes-recomendados)
10. [Configuración inicial y primer arranque](#10-configuración-inicial-y-primer-arranque)
11. [Mantenimiento](#11-mantenimiento-tras-git-pull)
12. [Lecciones aprendidas](#12-lecciones-aprendidas)

---

## 1. Por qué no se puede instalar desde apt

Hyprland no está empaquetado en Debian Trixie (ni en backports). Y aunque algunas
de sus dependencias sí lo están, las versiones que pide Hyprland 0.53 son más
nuevas que lo que Debian estabiliza:

| Dependencia            | Debian Trixie | Hyprland 0.53 pide |
| ---------------------- | ------------- | ------------------ |
| `xkbcommon`            | **1.7.0**     | ≥ **1.11.0**       |
| `wayland-protocols`    | **1.44**      | ≥ **1.45**         |
| `wayland-server`       | 1.23.1        | ≥ 1.22.90 ✓        |
| `libinput`             | 1.28.1        | ≥ 1.28 ✓           |
| `aquamarine`           | —             | ≥ 0.9.3            |
| `hyprutils`            | —             | ≥ 0.11.0           |
| `hyprlang`             | —             | ≥ 0.6.7            |
| `hyprcursor`           | —             | ≥ 0.1.7            |
| `hyprgraphics`         | —             | ≥ 0.1.6            |
| `hyprwire`             | —             | (cualquiera, dep. nueva en 0.53) |

Las dos bloqueantes son **xkbcommon 1.7 → 1.11** (cuatro minor versions detrás)
y **wayland-protocols 1.44 → 1.45** (una versión muy reciente). Las hypr-libs
no están empaquetadas en absoluto y hay que construirlas todas.

## 2. Resumen del problema y la solución

Compilar Hyprland 0.53 desde fuente con GCC 14.2 encuentra **dos clases de
problema**, ambos resolubles sin instalar GCC 15:

### 2.1 Versiones de librerías nativas demasiado bajas
- `xkbcommon` 1.7 → instalar 1.11 desde fuente en `/usr/local/`.
- `wayland-protocols` 1.44 → instalar 1.45 desde fuente en `/usr/local/`.

### 2.2 Features de C++23/C++26 ausentes en libstdc++ 14
GCC 14.2 acepta `-std=c++26` pero su libstdc++ no implementa todavía:

- **`#embed`** (preprocesador C23/C++26). Llegó en GCC 15.
- **`std::vector::append_range` / `insert_range`** (P1206, C++23). Llegó en libstdc++ 15.
- **`std::string + std::string_view`** (P2591, C++26). Llegó en libstdc++ 15.

Las solucionamos con parches mínimos al código (≈ 20 líneas en total).

### 2.3 Resto: solo orden de compilación
Las 7 hypr-libs forman un grafo de dependencias; hay que construirlas en orden.

## 3. Paquetes de Debian necesarios

Instala primero todo lo que sí está empaquetado. Es una lista larga porque
Hyprland enlaza con muchas librerías de gráficos, audio, X y misceláneos:

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake meson ninja-build pkg-config git python3 \
  libwayland-dev wayland-protocols libwayland-server0 wayland-scanner++ \
  libdrm-dev libgbm-dev libgles-dev libegl-dev libgl-dev \
  libinput-dev libudev-dev libseat-dev libdisplay-info-dev libliftoff-dev \
  libpixman-1-dev libcairo2-dev libpango1.0-dev libpangocairo-1.0-0 \
  libxcb1-dev libxcb-render0-dev libxcb-xfixes0-dev libxcb-icccm4-dev \
  libxcb-composite0-dev libxcb-res0-dev libxcb-errors-dev libxcb-cursor-dev \
  libxkbcommon-dev libxkbcommon-x11-dev xwayland \
  libxcursor-dev libuuid1 uuid-dev libpipewire-0.3-dev \
  libsystemd-dev libglib2.0-dev libgio-2.0-0 libgio-2.0-dev \
  libpugixml-dev libffi-dev libtomlplusplus-dev libre2-dev libmuparser-dev \
  libjpeg-dev libwebp-dev librsvg2-dev libmagic-dev libnotify-dev \
  libspng-dev libpoll-dev libcjson-dev
```

> Algunos `-dev` pueden ser opcionales según los componentes que actives en
> Hyprland (UWSM, hyprtester, hyprpm). Si CMake se queja de uno que falta,
> apt-cache search lo encontrará casi siempre.

A pesar de instalarlos, **vamos a sobrescribir** `xkbcommon` y `wayland-protocols`
en `/usr/local/`, porque sus versiones son insuficientes.

## 4. Orden de compilación

```
xkbcommon 1.11 ──┐
wayland-protocols 1.45 ──┐
                         ▼
                    hyprutils ──────┬──> hyprwayland-scanner
                                    │
                                    ├──> hyprlang
                                    │
                                    ├──> hyprcursor
                                    │
                                    └──> hyprgraphics ──> aquamarine
                                                            │
                                                            ▼
                                                         hyprwire
                                                            │
                                                            ▼
                                                         Hyprland
```

Yo lo hice en una sola carpeta:

```bash
mkdir -p ~/hyprbuild && cd ~/hyprbuild
for repo in xkbcommon wayland-protocols hyprutils hyprwayland-scanner \
            hyprlang hyprcursor hyprgraphics aquamarine hyprwire Hyprland; do
  case $repo in
    xkbcommon)         git clone --depth 1 -b xkbcommon-1.11.0 \
                         https://github.com/xkbcommon/libxkbcommon $repo ;;
    wayland-protocols) git clone --depth 1 -b 1.45 \
                         https://gitlab.freedesktop.org/wayland/wayland-protocols $repo ;;
    *)                 git clone --depth 1 https://github.com/hyprwm/$repo ;;
  esac
done
```

## 5. Compilar las dependencias from-source

Todas se instalan con prefijo `/usr/local` (CMake/Meson por defecto) — apt
nunca toca esa ruta, así que las actualizaciones de Debian no romperán nada.

### 5.1 xkbcommon 1.11.0 (Meson)
```bash
cd ~/hyprbuild/xkbcommon
meson setup build -Dprefix=/usr/local -Denable-docs=false
meson compile -C build -j2
sudo meson install -C build
sudo ldconfig
```

### 5.2 wayland-protocols 1.45 (Meson)
```bash
cd ~/hyprbuild/wayland-protocols
meson setup build -Dprefix=/usr/local -Dtests=false
meson compile -C build -j2
sudo meson install -C build
```
> Comprueba con `pkg-config --modversion wayland-protocols` que devuelve `1.45`.

### 5.3 hypr-libs (todas con el mismo patrón CMake)
Para cada una de `hyprutils`, `hyprwayland-scanner`, `hyprlang`, `hyprcursor`,
`hyprgraphics`, `aquamarine`:

```bash
cd ~/hyprbuild/<libreria>
cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE=Release -B build -G Ninja
cmake --build build -j2
sudo cmake --install build
sudo ldconfig
```

Versiones que se instalan con el `--depth 1` de hoy: hyprutils 0.11.0,
hyprwayland-scanner 0.4.5, hyprlang 0.6.8, hyprcursor 0.1.13,
hyprgraphics 0.5.0, aquamarine 0.10.0.

## 6. Parchar hyprwire para libstdc++ 14

hyprwire 0.2.1 usa `std::vector::append_range` (C++23, ausente en libstdc++ 14)
en **16 sitios** repartidos en 6 archivos. El error que verás:

```
error: ‘class std::vector<unsigned char>’ has no member named ‘append_range’
```

La sustitución segura es:

```cpp
// Antes
m_data.append_range(EXPR);

// Después
{ auto&& _r = EXPR; m_data.insert(m_data.end(), _r.begin(), _r.end()); }
```

El `auto&&` evita copia para lvalues y extiende la vida del temporal si `EXPR`
es rvalue (importante porque varias llamadas pasan `std::vector<...>{...}` o
`std::span(...)` temporales).

Script Python que aplica los 16 reemplazos (`scripts/patch-hyprwire.py`):

```python
import re, pathlib
base = pathlib.Path("~/hyprbuild/hyprwire").expanduser()
files = [
    "src/core/message/messages/BindProtocol.cpp",
    "src/core/message/messages/HandshakeBegin.cpp",
    "src/core/message/messages/FatalProtocolError.cpp",
    "src/core/message/messages/HandshakeProtocols.cpp",
    "src/core/socket/SocketHelpers.cpp",
    "src/core/wireObject/IWireObject.cpp",
]
pat = re.compile(r'^(\s*)([\w.]+)\.append_range\((.*)\);\s*$')
for rel in files:
    p = base / rel
    out = []
    for line in p.read_text().splitlines(keepends=True):
        m = pat.match(line)
        if m:
            indent, target, expr = m.groups()
            out.append(f"{indent}{{ auto&& _r = {expr}; {target}.insert({target}.end(), _r.begin(), _r.end()); }}\n")
        else:
            out.append(line)
    p.write_text("".join(out))
```

Luego compilar e instalar:
```bash
cd ~/hyprbuild/hyprwire
python3 scripts/patch-hyprwire.py
git diff > append_range-gcc14-compat.patch    # guarda el parche para futuros git pull
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
sudo cmake --install build && sudo ldconfig
```

## 7. Parchar Hyprland para GCC 14

Hyprland 0.53 tiene **cuatro tropiezos** con libstdc++ 14:

### 7.1 `#embed` en defaultConfig.hpp

```cpp
// src/config/defaultConfig.hpp:14-16  ANTES
inline constexpr char EXAMPLE_CONFIG_BYTES[] = {
    #embed "../../example/hyprland.conf"
};
```

`#embed` es un directivo C23/C++26 que llegó en GCC 15.

**Fix**: generar previamente un `.inc` con los bytes en hex e incluirlo.

```bash
python3 -c "
import pathlib
data = pathlib.Path('example/hyprland.conf').read_bytes()
rows = []
for i in range(0, len(data), 16):
    rows.append(', '.join(f'0x{b:02x}' for b in data[i:i+16]))
pathlib.Path('src/config/example_hyprland_conf_bytes.inc').write_text(',\n'.join(rows) + '\n')
"
```

Y editar `defaultConfig.hpp`:
```cpp
inline constexpr char EXAMPLE_CONFIG_BYTES[] = {
    #include "example_hyprland_conf_bytes.inc"
};
```

### 7.2 Ternary entre tipo con `operator T*()` y `nullptr`

```cpp
// src/xwayland/XWM.hpp:217  ANTES
return m_connection ? *m_connection : nullptr;
```

`CXCBConnection` tiene `operator xcb_connection_t*()`. GCC 14 no aplica la
conversión definida por el usuario en `?:`. Fix con cast explícito:

```cpp
return m_connection ? static_cast<xcb_connection_t*>(*m_connection) : nullptr;
```

### 7.3 `vector::insert_range`

```cpp
// src/helpers/Monitor.cpp:635  ANTES
requestedModes.insert_range(requestedModes.end(), sortedModes | std::views::reverse);
```

Misma falta que en hyprwire. Fix:

```cpp
{ auto&& _r = sortedModes | std::views::reverse;
  requestedModes.insert(requestedModes.end(), _r.begin(), _r.end()); }
```

### 7.4 `std::string + std::string_view`

```cpp
// hyprctl/src/main.cpp:274  ANTES
std::string socketPath = getRuntimeDir() + "/" + instanceSignature + "/" + filename;
```

`filename` es `std::string_view`. Sumar `string + string_view` requiere C++26
(operador añadido en libstdc++ 15). Fix:

```cpp
std::string socketPath = getRuntimeDir() + "/" + instanceSignature + "/" + std::string(filename);
```

## 8. Compilar e instalar Hyprland

```bash
cd ~/hyprbuild/Hyprland
# (aplicar los 4 parches del paso 7 antes)
cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE=Release -B build -G Ninja
cmake --build build -j2    # ≈ 20 min con i3-8130U / 4 GiB
sudo cmake --install build
sudo ldconfig
```

Verificar:
```bash
$ Hyprland --version
Hyprland 0.53.0 built from branch main at commit 918e2bb9...
Libraries:
Hyprgraphics: built against 0.5.0, system has 0.5.0
Hyprutils: built against 0.11.0, system has 0.11.0
Hyprcursor: built against 0.1.13, system has 0.1.13
Hyprlang: built against 0.6.8, system has 0.6.8
Aquamarine: built against 0.10.0, system has 0.10.0
```

El install coloca los binarios en `/usr/local/bin/` y las **sesiones**
`hyprland.desktop` y `hyprland-uwsm.desktop` en
`/usr/local/share/wayland-sessions/`. GDM las recoge automáticamente porque
escanea tanto `/usr/share/wayland-sessions/` como `/usr/local/share/wayland-sessions/`.

> **Nota sobre `-j`**: con 4 GiB de RAM y `-j2` la compilación es estable.
> Con `-j4` he visto OOM kills sobre `cc1plus` (cada instancia gasta
> 1-1.5 GiB en Hyprland). Si tienes 8+ GiB, `-j$(nproc)` está bien.

## 9. Acompañantes recomendados

Hyprland es solo el compositor. Para una experiencia mínima usable necesitas
al menos terminal, lanzador, barra de estado y notificaciones — todos están
en Debian:

```bash
sudo apt install -y kitty wofi waybar mako-notifier
```

### Wallpaper: `hyprpaper` 0.7.5 (no la 0.8+)

La versión 0.8 de hyprpaper añade dependencia de `hyprtoolkit`, que a su vez
trae iniparser, abseil y más cadena. **Para uso normal, hyprpaper 0.7.5 es
suficiente** y solo necesita las hypr-libs que ya tienes.

```bash
cd ~/hyprbuild
git clone https://github.com/hyprwm/hyprpaper && cd hyprpaper
git checkout v0.7.5
cmake -DCMAKE_BUILD_TYPE=Release -B build -G Ninja
cmake --build build -j2
sudo cmake --install build
```

> hyprpaper 0.7.5 usa solo C++23 y **no requiere parches** en GCC 14.

## 10. Configuración inicial y primer arranque

```bash
mkdir -p ~/.config/hypr
cp ~/hyprbuild/Hyprland/example/hyprland.conf ~/.config/hypr/hyprland.conf
```

Editar `~/.config/hypr/hyprland.conf` y añadir (busca la sección
"Autostart" comentada cerca de la línea 40):

```ini
exec-once = hyprpaper
exec-once = waybar
exec-once = mako
```

Crear `~/.config/hypr/hyprpaper.conf`:

```ini
preload   = /usr/share/backgrounds/gnome/adwaita-d.jpg
wallpaper = ,/usr/share/backgrounds/gnome/adwaita-d.jpg
splash    = false
ipc       = off
```

**Arranque**: cerrar sesión de GNOME → en GDM clicar el engranaje ⚙️ junto al
campo de contraseña → elegir **Hyprland** → contraseña → Enter.

Atajos por defecto del config de ejemplo:
- `Super + Q`: terminal (kitty)
- `Super + R`: lanzador (wofi)
- `Super + C`: cerrar ventana
- `Super + M`: salir de Hyprland

Si la pantalla queda negra y vuelves a GDM, mirar `~/.cache/hyprland/hyprland.log`.

## 11. Mantenimiento tras `git pull`

Los parches se guardan como ficheros `.patch` y un script aplicador. Tras
actualizar el código:

```bash
# hyprwire
cd ~/hyprbuild/hyprwire && git pull
git apply append_range-gcc14-compat.patch
cmake --build build -j2 && sudo cmake --install build

# Hyprland
cd ~/hyprbuild/Hyprland && git pull
./apply-gcc14-compat.sh    # regenera el .inc y aplica el .patch
cmake --build build -j2 && sudo cmake --install build
```

Si upstream tocó alguna de las líneas parchadas, `git apply` fallará — habrá
que ver el reject y rehacer a mano (o esperar a que upstream añada compat
para libstdc++ < 15).

## 12. Lecciones aprendidas

1. **CMake hardcodea rutas absolutas en `cmake_install.cmake`**. Si mueves
   una carpeta build después de configurar, install fallará. Borrar `build/`
   y reconfigurar.
2. **GCC 14 acepta `-std=c++26` pero la libstdc++ es la que dicta qué
   compila**. Soportar el dialecto no implica tener el runtime.
3. **`#embed` se puede emular con `python -c '...'` + `#include`** sin perder
   propiedades (es `constexpr` y se compila a memoria embebida igual).
4. **`auto&&`** es el truco para sustituir cualquier `*_range` sin perder
   eficiencia ni vidas: lvalue → referencia, rvalue → vida extendida.
5. **`/usr/local/` es el cinturón de seguridad** frente a actualizaciones de
   apt — todo lo de manualmente compilado va ahí y nunca colisiona con la
   distro.
6. **Empezar desde la versión más vieja que cubra tus necesidades** (caso de
   hyprpaper 0.7.5 vs 0.8+) ahorra noches enteras. Los proyectos hyprwm
   evolucionan rápido y cada minor añade dependencias.

---

## Archivos generados por esta guía

- `~/.config/hypr/hyprland.conf` — configuración del compositor
- `~/.config/hypr/hyprpaper.conf` — configuración del wallpaper
- `~/hyprbuild/hyprwire/append_range-gcc14-compat.patch`
- `~/hyprbuild/Hyprland/hyprland-gcc14-compat.patch`
- `~/hyprbuild/Hyprland/apply-gcc14-compat.sh`
- `~/hyprbuild/Hyprland/src/config/example_hyprland_conf_bytes.inc` (generado)

## Licencia y créditos

Esta guía describe el proceso seguido para instalar Hyprland en una máquina
concreta. El código de Hyprland, hyprwire, hyprutils, hyprlang, hyprcursor,
hyprgraphics, aquamarine, hyprpaper, hyprwayland-scanner y hyprtoolkit
pertenece a sus respectivos autores (hyprwm/contributors), bajo BSD-3-Clause.
xkbcommon es MIT/X11. wayland-protocols es MIT.

Comparte la guía si te ahorró tiempo. Si encuentras un paso que ya no
encaja (porque GCC 15 llegó a Trixie, o porque Hyprland 0.54 cambió de
dependencias), abre un PR o issue.
