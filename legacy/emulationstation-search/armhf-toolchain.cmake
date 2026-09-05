# CMake toolchain for cross-building EmulationStation for a Pi 2/3.
#
# cmake itself runs natively on x86 here, which is the whole point:
# under Docker's ARM emulation cmake's file(GLOB) silently returns
# nothing, which breaks compiler detection and makes find_package()
# miss libraries without saying so.
#
# SYSROOT is the RetroPie image's own root filesystem, so we link
# against the exact libraries that will be on the Pi -- including
# /opt/vc's bcm_host, which -DRPI=On needs.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(TC_PREFIX arm-linux-gnueabihf)
set(CMAKE_C_COMPILER   ${TC_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TC_PREFIX}-g++)

set(CMAKE_SYSROOT "$ENV{SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "$ENV{SYSROOT}")

# Look for programs on the host, but headers/libraries only in the sysroot.
# (Valid values are NEVER / ONLY / BOTH -- NEVER means "don't look in the
# sysroot", i.e. use host programs, which is what we want for tools.)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The Pi 2/3 is ARMv7 with NEON and hardware float.
set(RPI_FLAGS "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard")
set(CMAKE_C_FLAGS_INIT   "${RPI_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${RPI_FLAGS}")

# /opt/vc holds the VideoCore firmware libraries, outside the normal
# library search paths.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-Wl,-rpath-link,$ENV{SYSROOT}/opt/vc/lib -L$ENV{SYSROOT}/opt/vc/lib -Wl,-rpath-link,$ENV{SYSROOT}/usr/lib/arm-linux-gnueabihf")
