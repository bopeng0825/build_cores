#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "ROOT=$ROOT"
echo "TOOLCHAIN=$TOOLCHAIN"

which mips-mti-linux-gnu-gcc
mips-mti-linux-gnu-gcc --version

# ===================== 在这里勾选需要编译的核心 =====================
# 格式：空格分隔，只写第一个参数（_b 的 name 名称）
DEFAULT_BUILD_LIST=(
    fceumm
    quicknes
    snes9x2005_plus
    gpsp_multicore
    gpsp
)

if [ "$#" -eq 0 ]; then
    BUILD_LIST=("${DEFAULT_BUILD_LIST[@]}")
else
    BUILD_LIST=("$@")
fi
# ====================================================================

# 判断函数：是否启用该核心
_is_build() {
    local name="$1"
    for item in "${BUILD_LIST[@]}"; do
        if [[ "$item" == "$name" ]]; then
            return 0 # 需要编译
        fi
    done
    return 1 # 跳过
}

# 工具链路径
TOOLCHAIN="${TOOLCHAIN:-/opt/mipsel-buildroot-linux-gnu_sdk-buildroot}"
MIPS="$TOOLCHAIN/opt/ext-toolchain/bin/mips-mti-linux-gnu-"
SYSROOT="$TOOLCHAIN/mipsel-buildroot-linux-gnu/sysroot"
OUT="$ROOT/build"
CORES="$ROOT/cores"
WRAP="$ROOT/.toolchain"

mkdir -p "$OUT" "$WRAP"

# 基础MIPS编译标记
SF3000_FLAGS="-mips32r2 -march=mips32r2 -mtune=74kc -mdspr2 -mfp32 -mhard-float -mlong-calls -EL --sysroot=$SYSROOT -Ofast -DNDEBUG"

# 生成各类编译器wrapper
cat > "$WRAP/mips-gcc" <<EOF
#!/bin/bash
exec ${MIPS}gcc $SF3000_FLAGS "\$@"
EOF
cat > "$WRAP/mips-g++" <<EOF
#!/bin/bash
exec ${MIPS}g++ $SF3000_FLAGS "\$@"
EOF

cat > "$WRAP/gpsp-gcc" <<EOF
#!/bin/bash
exec ${MIPS}gcc --sysroot=$SYSROOT -isystem $SYSROOT/usr/include -fPIC -EL "\$@"
EOF
cat > "$WRAP/gpsp-g++" <<EOF
#!/bin/bash
exec ${MIPS}g++ --sysroot=$SYSROOT -isystem $SYSROOT/usr/include -fPIC -EL "\$@"
EOF

cat > "$WRAP/mips-gcc-O3" <<EOF
#!/bin/bash
exec ${MIPS}gcc $SF3000_FLAGS "\$@" -O3
EOF
cat > "$WRAP/mips-g++-O3" <<EOF
#!/bin/bash
exec ${MIPS}g++ $SF3000_FLAGS "\$@" -O3
EOF

# FBA专用编译参数
FBA_FLAGS="$(echo "$SF3000_FLAGS" | sed 's/-mdspr2 //')"
FBA_FIX="-fno-strict-aliasing -fsigned-char"
cat > "$WRAP/fba-gcc" <<EOF
#!/bin/bash
exec ${MIPS}gcc $FBA_FLAGS "\$@" $FBA_FIX
EOF
cat > "$WRAP/fba-g++" <<EOF
#!/bin/bash
exec ${MIPS}g++ $FBA_FLAGS "\$@" $FBA_FIX
EOF

chmod +x "$WRAP"/mips-gcc "$WRAP"/mips-g++ "$WRAP"/gpsp-gcc "$WRAP"/gpsp-g++ \
         "$WRAP"/mips-gcc-O3 "$WRAP"/mips-g++-O3 "$WRAP"/fba-gcc "$WRAP"/fba-g++

# 全局链接参数
AR="${MIPS}ar"
RANLIB="${MIPS}ranlib"
STRIP="${MIPS}strip"
LDFLAGS="-mips32r2 -mhard-float -mfp32 -EL --sysroot=$SYSROOT -L$SYSROOT/usr/lib -lm -lc -lstdc++"
LDFLAGS_C="-mips32r2 -mhard-float -mfp32 -EL --sysroot=$SYSROOT -L$SYSROOT/usr/lib -lm -lc"
LDFLAGS_S="-shared -Wl,--no-undefined -mips32r2 -mhard-float -mfp32 -EL --sysroot=$SYSROOT -L$SYSROOT/usr/lib -lm -lc -lstdc++"
LDFLAGS_SC="-shared -Wl,--no-undefined -mips32r2 -mhard-float -mfp32 -EL --sysroot=$SYSROOT -L$SYSROOT/usr/lib -lm -lc"

# 通用libretro核心编译函数
_b() {
    local name="$1" dir="$2" mk="${3:-}" extra="${4:-}"
    if ! _is_build "$name"; then
        echo "skip $name (not in BUILD_LIST)"
        return
    fi
    local cw="${CC_WRAP:-mips}"
    echo "-- $name make --"
    local full="$CORES/$dir"
    make -C "$full" $mk clean 2>/dev/null || true
    make -C "$full" $mk platform=unix \
        CC="$WRAP/$cw-gcc" CXX="$WRAP/$cw-g++" \
        AR="$AR" RANLIB="$RANLIB" LD="$WRAP/$cw-g++" \
        LDFLAGS="$LDFLAGS" $extra -j$(nproc) 2>&1
    local so
    for so in \
        "$full/${name}_libretro.so" \
        "$full/$(basename "$dir")_libretro.so"; do
        [ -f "$so" ] && cp "$so" "$OUT/${name}_libretro.so" && \
            "$STRIP" "$OUT/${name}_libretro.so" && \
            echo "→ $OUT/${name}_libretro.so" && return
    done
    echo "WARNING: .so not found for $name"
}

# Angree SF2000移植核心专用编译函数
_b_angree() {
    local name="$1" dir="$2" mk="$3"
    if ! _is_build "$name"; then
        echo "skip $name (not in BUILD_LIST)"
        return
    fi
    echo "-- $name make --"
    local full="$CORES/$dir"
    make -C "$full" $mk clean 2>/dev/null || true
    make -C "$full" $mk \
        CC="$WRAP/mips-gcc" CXX="$WRAP/mips-g++" \
        AR="$AR" RANLIB="$RANLIB" LD="$WRAP/mips-g++" \
        LDFLAGS="$LDFLAGS_SC" -j$(nproc) 2>&1
    local so
    for so in \
        "$full/${name}_libretro.so" \
        "$full/$(basename "$dir")_libretro.so"; do
        [ -f "$so" ] && cp "$so" "$OUT/${name}_libretro.so" && \
            "$STRIP" "$OUT/${name}_libretro.so" && \
            echo "→ $OUT/${name}_libretro.so" && return
    done
    echo "WARNING: .so not found for $name"
}

# ===================== 所有核心编译调用 =====================
_b fceumm            fceumm                    "-f Makefile.libretro"
_b quicknes          QuickNES_Core             ""
_b snes9x2005_plus   snes9x2005                "" "CC=$WRAP/mips-gcc-O3 CXX=$WRAP/mips-g++-O3"
_b snes9x2002        snes9x2002                ""
_b snes9x2010        snes9x2010                "-f Makefile.libretro" "LTO="
_b gambatte          libretro-gambatte         "-f Makefile.libretro"

# gpsp multicore
if _is_build "gpsp_multicore"; then
echo "-- gpsp_multicore make --"
make -C "$CORES/gpsp" clean 2>/dev/null || true
make -C "$CORES/gpsp" platform=sf3000 \
    CC="$WRAP/gpsp-gcc" CXX="$WRAP/gpsp-g++" \
    AR="$AR" RANLIB="$RANLIB" LD="$WRAP/gpsp-gcc" \
    LDFLAGS="$LDFLAGS_C" -j$(nproc) 2>&1
[ -f "$CORES/gpsp/gpsp_libretro.so" ] && \
    cp "$CORES/gpsp/gpsp_libretro.so" "$OUT/gpsp_multicore_libretro.so" && \
    "$STRIP" "$OUT/gpsp_multicore_libretro.so" && echo "→ $OUT/gpsp_multicore_libretro.so"
else
    echo "skip gpsp_multicore"
fi

# gpsp upstream
if _is_build "gpsp"; then
echo "-- gpsp make --"
make -C "$CORES/gpsp_upstream" clean 2>/dev/null || true
make -C "$CORES/gpsp_upstream" platform=sf3000 \
    CC="$WRAP/gpsp-gcc" CXX="$WRAP/gpsp-g++" \
    AR="$AR" RANLIB="$RANLIB" -j$(nproc) 2>&1 || true
rm -f "$CORES/gpsp_upstream/gpsp_libretro.so"
make -C "$CORES/gpsp_upstream" platform=sf3000 \
    CC="$WRAP/gpsp-g++" CXX="$WRAP/gpsp-g++" \
    AR="$AR" RANLIB="$RANLIB" \
    LDFLAGS="$LDFLAGS_C -lstdc++" gpsp_libretro.so 2>&1
[ -f "$CORES/gpsp_upstream/gpsp_libretro.so" ] && \
    cp "$CORES/gpsp_upstream/gpsp_libretro.so" "$OUT/gpsp_libretro.so" && \
    "$STRIP" "$OUT/gpsp_libretro.so" && echo "→ $OUT/gpsp_libretro.so"
else
    echo "skip gpsp"
fi

_b picodrive         picodrive                 "-f Makefile.libretro"
_b mgba              mgba                      "-f Makefile.libretro"
_b genesis_plus_gx   Genesis-Plus-GX           "-f Makefile.libretro"
_b tyrquake          tyrquake                  ""
_b prboom            libretro-prboom           ""
_b mame2000          mame2000                  ""

CC_WRAP=fba _b fbalpha2012_cps1   fbalpha2012_cps1   ""
CC_WRAP=fba _b fbalpha2012_cps2   fbalpha2012_cps2   ""
CC_WRAP=fba _b fbalpha2012_cps3   fbalpha2012_cps3/svn-current/trunk   "-f makefile.libretro"
CC_WRAP=fba _b fbalpha2012_neogeo fbalpha2012_neogeo ""

_b mame2003_plus     mame2003-plus-libretro    "" "LDFLAGS=$LDFLAGS_S"
CC_WRAP=fba _b fbneo FBNeo/src/burner/libretro  "" "LDFLAGS=$LDFLAGS_S -lpthread"
_b stella2014        stella2014                "" "LDFLAGS=$LDFLAGS_S"
_b prosystem         prosystem                 "" "LDFLAGS=$LDFLAGS_S"
_b nestopia          nestopia/libretro         ""
_b tgbdual           libretro-tgbdual          ""
_b gearboy           Gearboy/platforms/libretro ""
_b pokemini          PokeMini                  ""
_b vba_next          vba-next                  ""
_b cannonball        cannonball                "" "LDFLAGS=$LDFLAGS_S"
_b ecwolf            ecwolf/src/libretro       "" "LDFLAGS=$LDFLAGS_S"
_b pocketcdg         libretro-pocketcdg        ""
_b race              RACE                      ""
_b mednafen_pce_fast libretro-beetle-pce-fast  "" "LDFLAGS=$LDFLAGS_S"
_b mednafen_wswan    libretro-beetle-wswan     "" "LDFLAGS=$LDFLAGS_S"
_b mednafen_lynx     libretro-beetle-lynx      "" "LDFLAGS=$LDFLAGS_S"
_b mednafen_vb       libretro-beetle-vb        "" "LDFLAGS=$LDFLAGS_S"
_b mednafen_supergrafx libretro-beetle-supergrafx "" "LDFLAGS=$LDFLAGS_S"
_b mednafen_pcfx     libretro-beetle-pcfx      "" "LDFLAGS=$LDFLAGS_S -lpthread"
_b handy             libretro-handy            ""
_b a5200             a5200                     ""
_b 81                libretro-81               ""
_b fuse              libretro-fuse             ""
_b potator           potator/platform/libretro ""
_b theodore          theodore                  ""
_b gearcoleco        Gearcoleco/platforms/libretro ""
_b gearsystem        Gearsystem/platforms/libretro ""
_b freechaf          FreeChaF                  "" "LDFLAGS=$LDFLAGS_SC"
_b freeintv          FreeIntv                  ""
_b gme               libretro-gme              ""
_b cap32             libretro-cap32            ""
_b crocods           libretro-crocods          ""
_b gw                libretro-gw               ""
_b xrick             libretro-xrick            ""
_b reminiscence      REminiscence              ""
_b nxengine          libretro-nxengine         ""
_b jumpnbump         libretro-jumpnbump        ""
_b lowresnx          lowres-nx/platform/LibRetro ""
_b retro8            retro8                    ""
_b fake08            fake-08/platform/libretro "" "CC=$WRAP/mips-gcc-O3 CXX=$WRAP/mips-g++-O3"

# PCSX Rearmed
if _is_build "pcsx_rearmed"; then
echo "-- pcsx_rearmed make --"
git -C "$CORES/pcsx_rearmed" submodule update --init --depth=1 frontend/libpicofe 2>/dev/null || true
make -C "$CORES/pcsx_rearmed" -f Makefile.libretro clean 2>/dev/null || true
make -C "$CORES/pcsx_rearmed" -f Makefile.libretro platform=unix \
    CC="$WRAP/mips-gcc" CXX="$WRAP/mips-g++" CC_AS="$WRAP/mips-gcc" CC_LINK="$WRAP/mips-g++" \
    AR="$AR" ARCH=mips DYNAREC=lightrec HAVE_NEON=0 BUILTIN_GPU=unai -j"$(nproc)" 2>&1
if [ -f "$CORES/pcsx_rearmed/pcsx_rearmed_libretro.so" ]; then
    cp "$CORES/pcsx_rearmed/pcsx_rearmed_libretro.so" "$OUT/pcsx_rearmed_libretro.so"
    "$STRIP" "$OUT/pcsx_rearmed_libretro.so"
    echo "→ $OUT/pcsx_rearmed_libretro.so"
else
    echo "WARNING: .so not found for pcsx_rearmed"
fi
else
    echo "skip pcsx_rearmed"
fi

_b gong              gong                      "-f Makefile.libretro"
_b quasi88           libretro-quasi88          ""
_b geolith           libretro-geolith/libretro "" "LDFLAGS=$LDFLAGS_S"
_b x68k              libretro-xmil/libretro    ""
_b atari800          libretro-atari800         "-f Makefile.libretro"

# Frodo C64
if _is_build "frodo"; then
echo "-- frodo make --"
git -C "$CORES/libretro-frodo" submodule update --init --recursive 2>/dev/null || true
make -C "$CORES/libretro-frodo" clean 2>/dev/null || true
find "$CORES/libretro-frodo" -name "*.o" -delete 2>/dev/null || true
make -C "$CORES/libretro-frodo" platform=unix NOLIBCO=1 \
    CC="$WRAP/mips-gcc" CXX="$WRAP/mips-g++" \
    AR="$AR" RANLIB="$RANLIB" LD="$WRAP/mips-g++" \
    LDFLAGS="$LDFLAGS_S -Wl,--allow-multiple-definition" -j$(nproc) 2>&1
[ -f "$CORES/libretro-frodo/frodo_libretro.so" ] && \
    cp "$CORES/libretro-frodo/frodo_libretro.so" "$OUT/" && \
    "$STRIP" "$OUT/frodo_libretro.so" && echo "→ $OUT/frodo_libretro.so" || \
    echo "WARNING: .so not found for frodo"
else
    echo "skip frodo"
fi

# UAE Amiga
if _is_build "uae"; then
echo "-- uae make --"
make -C "$CORES/sf2000-uae-amiga-emulator" -f Makefile.libretro clean 2>/dev/null || true
make -C "$CORES/sf2000-uae-amiga-emulator" -f Makefile.libretro \
    CC="$WRAP/mips-gcc" CXX="$WRAP/mips-g++" \
    AR="$AR" RANLIB="$RANLIB" LD="$WRAP/mips-g++" \
    LDFLAGS="$LDFLAGS_SC -lz -lstdc++" -j$(nproc) 2>&1
[ -f "$CORES/sf2000-uae-amiga-emulator/uae4all_libretro.so" ] && \
    cp "$CORES/sf2000-uae-amiga-emulator/uae4all_libretro.so" "$OUT/uae_libretro.so" && \
    "$STRIP" "$OUT/uae_libretro.so" && echo "→ $OUT/uae_libretro.so"
else
    echo "skip uae"
fi

_b_angree castaway    sf2000-atarist-emulator                "-f Makefile.libretro"

# 输出编译完成列表
echo ""
echo "Done. Built cores:"
ls "$OUT"/*.so 2>/dev/null | xargs -I{} basename {}