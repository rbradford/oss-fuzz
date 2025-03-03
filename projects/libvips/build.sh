#!/bin/bash -eu
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

export PKG_CONFIG="pkg-config --static"
export PKG_CONFIG_PATH="$WORK/lib/pkgconfig"
export CPPFLAGS="-I$WORK/include"
export LDFLAGS="-L$WORK/lib"

# libz
pushd $SRC/zlib
./configure --static --prefix=$WORK
make -j$(nproc) all
make install
popd

# libexif
pushd $SRC/libexif
autoreconf -fi
./configure \
  --enable-static \
  --disable-shared \
  --disable-nls \
  --disable-docs \
  --disable-dependency-tracking \
  --prefix=$WORK
make -j$(nproc)
make install
popd

# lcms
pushd $SRC/lcms
./autogen.sh
./configure \
  --enable-static \
  --disable-shared \
  --disable-dependency-tracking \
  --prefix=$WORK
make -j$(nproc)
make install
popd

# aom
pushd $SRC/aom
mkdir -p build/linux
cd build/linux
extra_libaom_flags='-DAOM_MAX_ALLOCABLE_MEMORY=536870912 -DDO_RANGE_CHECK_CLAMP=1'
cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=$WORK \
  -DCONFIG_PIC=1 \
  -DENABLE_EXAMPLES=0 \
  -DENABLE_DOCS=0 \
  -DENABLE_TESTS=0 \
  -DENABLE_TOOLS=0 \
  -DCONFIG_SIZE_LIMIT=1 \
  -DDECODE_HEIGHT_LIMIT=12288 \
  -DDECODE_WIDTH_LIMIT=12288 \
  -DAOM_EXTRA_C_FLAGS="$extra_libaom_flags" \
  -DAOM_EXTRA_CXX_FLAGS="$extra_libaom_flags" \
  -DAOM_TARGET_CPU=generic \
  ../../
make clean
make -j$(nproc)
make install
popd

# libheif
pushd $SRC/libheif
# Ensure libvips finds heif_image_handle_get_raw_color_profile
sed -i '/^Libs.private:/s/-lstdc++/-lc++/' libheif.pc.in
autoreconf -fi
./configure \
  --disable-shared \
  --enable-static \
  --disable-examples \
  --disable-go \
  --prefix=$WORK
make clean
make -j$(nproc)
make install
popd

# libjpeg-turbo
pushd $SRC/libjpeg-turbo
cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=$WORK \
  -DENABLE_STATIC=TRUE \
  -DENABLE_SHARED=FALSE \
  -DWITH_TURBOJPEG=FALSE \
  .
make -j$(nproc)
make install
popd

# libpng
pushd $SRC/libpng
sed -ie 's/option WARNING /& disabled/' scripts/pnglibconf.dfa
autoreconf -fi
./configure \
  --prefix=$WORK \
  --disable-shared \
  --disable-dependency-tracking
make -j$(nproc)
make install
popd

# libspng
pushd $SRC/libspng
meson setup build --prefix=$WORK --libdir=lib --default-library=static --buildtype=debugoptimized \
  -Dstatic_zlib=true
ninja -C build
ninja -C build install
popd

# libwebp
pushd $SRC/libwebp
autoreconf -fi
./configure \
  --enable-libwebpdemux \
  --enable-libwebpmux \
  --disable-shared \
  --disable-jpeg \
  --disable-tiff \
  --disable-gif \
  --disable-wic \
  --disable-threading \
  --disable-dependency-tracking \
  --prefix=$WORK
make -j$(nproc)
make install
popd

# libtiff ... a bug in libtiff master as of 20 Nov 2019 means we have to 
# explicitly disable lzma
pushd $SRC/libtiff
autoreconf -fi
./configure \
  --disable-lzma \
  --disable-shared \
  --disable-dependency-tracking \
  --prefix=$WORK
make -j$(nproc)
make install
popd

# jpeg-xl (libjxl)
pushd $SRC/libjxl
# Ensure libvips finds JxlEncoderInitBasicInfo
sed -i '/^Libs.private:/ s/$/ -lc++/' lib/jxl/libjxl.pc.in
# FIXME: Remove the `-DHWY_DISABLED_TARGETS=HWY_SSSE3` workaround, see:
# https://github.com/libjxl/libjxl/issues/858
extra_libjxl_flags='-DHWY_DISABLED_TARGETS=HWY_SSSE3'
cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_FLAGS="$CPPFLAGS $CFLAGS $extra_libjxl_flags" \
  -DCMAKE_CXX_FLAGS="$CPPFLAGS $CXXFLAGS $extra_libjxl_flags" \
  -DCMAKE_INSTALL_PREFIX=$WORK \
  -DZLIB_ROOT=$WORK \
  -DBUILD_SHARED_LIBS=0 \
  -DBUILD_TESTING=0 \
  -DJPEGXL_FORCE_SYSTEM_LCMS2=1 \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=1 \
  -DJPEGXL_ENABLE_FUZZERS=0 \
  -DJPEGXL_ENABLE_TOOLS=0 \
  -DJPEGXL_ENABLE_MANPAGES=0 \
  -DJPEGXL_ENABLE_BENCHMARK=0 \
  -DJPEGXL_ENABLE_EXAMPLES=0 \
  -DJPEGXL_ENABLE_SKCMS=0 \
  -DJPEGXL_ENABLE_SJPEG=0 \
  .
make -j$(nproc)
make install
popd

# libimagequant
pushd $SRC/libimagequant
meson setup build --prefix=$WORK --libdir=lib --default-library=static --buildtype=debugoptimized
ninja -C build
ninja -C build install
popd

# cgif
pushd $SRC/cgif
meson setup build --prefix=$WORK --libdir=lib --default-library=static --buildtype=debugoptimized
ninja -C build
ninja -C build install
popd

# pdfium doesn't need fuzzing, but we want to fuzz the libvips/pdfium link
pushd $SRC/pdfium-latest
cp lib/* $WORK/lib
cp -r include/* $WORK/include
popd

# make a pdfium.pc that libvips can use ... the version number just needs to
# be higher than 4200 to satisfy libvips
cat > $WORK/lib/pkgconfig/pdfium.pc << EOF
  prefix=$WORK
  exec_prefix=\${prefix}
  libdir=\${exec_prefix}/lib
  includedir=\${prefix}/include
  Name: pdfium
  Description: pdfium
  Version: 4901
  Requires:
  Libs: -L\${libdir} -lpdfium
  Cflags: -I\${includedir}
EOF

# libvips
# Disable building man pages, gettext po files, tools, and tests
sed -i "/subdir('man')/{N;N;N;N;d;}" meson.build
meson setup build --prefix=$WORK --libdir=lib --default-library=static \
  -Ddeprecated=false -Dintrospection=false -Dmodules=disabled
ninja -C build
ninja -C build install

# All shared libraries needed during fuzz target execution should be inside the $OUT/lib directory
mkdir -p $OUT/lib
cp $WORK/lib/*.so $OUT/lib

# Merge the seed corpus in a single directory, exclude files larger than 2k
mkdir -p fuzz/corpus
find \
  $SRC/afl-testcases/{gif*,jpeg*,png,tiff,webp}/full/images \
  fuzz/*_fuzzer_corpus \
  test/test-suite/images \
  -type f -size -2k \
  -exec bash -c 'hash=($(sha1sum {})); mv {} fuzz/corpus/$hash' ';'
zip -jrq $OUT/seed_corpus.zip fuzz/corpus

# Build fuzzers and link corpus
for fuzzer in fuzz/*_fuzzer.cc; do
  target=$(basename "$fuzzer" .cc)
  $CXX $CXXFLAGS -std=c++11 "$fuzzer" -o "$OUT/$target" \
    $CPPFLAGS \
    -I/usr/include/glib-2.0 \
    -I/usr/lib/x86_64-linux-gnu/glib-2.0/include \
    $LDFLAGS \
    -lvips -lexif -llcms2 -ljpeg -lpng -lspng -lz \
    -ltiff -lwebpmux -lwebpdemux -lwebp -lsharpyuv -lheif -laom \
    -ljxl -ljxl_threads -lhwy -limagequant -lcgif -lpdfium \
    $LIB_FUZZING_ENGINE \
    -Wl,-Bstatic \
    -lfftw3 -lexpat -lbrotlienc -lbrotlidec -lbrotlicommon \
    -lgio-2.0 -lgmodule-2.0 -lgobject-2.0 -lffi -lglib-2.0 \
    -lresolv -lmount -lblkid -lselinux -lsepol -lpcre \
    -Wl,-Bdynamic -pthread \
    -Wl,-rpath,'$ORIGIN/lib'
  ln -sf "seed_corpus.zip" "$OUT/${target}_seed_corpus.zip"
done

# Copy options and dictionary files to $OUT
find fuzz -name '*_fuzzer.dict' -exec cp -v '{}' $OUT ';'
find fuzz -name '*_fuzzer.options' -exec cp -v '{}' $OUT ';'
