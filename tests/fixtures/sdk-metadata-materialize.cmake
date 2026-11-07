# usage: shipyard-cmake -DMODULES=<shipyard cmake dir> -DSDK=<abs sdk> -DRECIPES=<abs json> -DIDS=<id;...>
#                       -DOUT=<abs dir, absent> -P sdk-metadata-materialize.cmake
# spec: tests/sdk-metadata-compile.sh -- the overlay a product would get, made by shipyard's own module
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULES}")
include(MavericksSDKMetadata)
mavericks_materialize_sdk_metadata(overlay SDK "${SDK}" RECIPES "${RECIPES}" IDS ${IDS} OUTPUT_DIR "${OUT}")
message("${overlay}")
