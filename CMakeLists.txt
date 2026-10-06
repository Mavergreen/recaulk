cmake_minimum_required(VERSION 3.16)
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9 CACHE STRING "runs on 10.9")
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "Intel-only (10.9)")

project(RecaulkUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)
include(MavericksSparkle)

if(NOT DEFINED RECAULK_VERSION)
  if(EXISTS "${CMAKE_SOURCE_DIR}/VERSION")
    file(STRINGS "${CMAKE_SOURCE_DIR}/VERSION" RECAULK_VERSION LIMIT_COUNT 1)
  else()
    file(STRINGS "${CMAKE_SOURCE_DIR}/UPSTREAM_VERSION" RECAULK_VERSION LIMIT_COUNT 1)
  endif()
endif()

mavericks_add_updater_app(
  PRODUCT recaulk
  PRODUCT_NAME "Recaulk for Mavericks"
  ICON "${CMAKE_SOURCE_DIR}/updater/recaulk-updater.icns"
  VERSION "${RECAULK_VERSION}"
  LOG_PREFIX "RecaulkUpdater"
  CONFIRM_TITLE "Recaulk for Mavericks updated"
  CONFIRM_BODY "The libraries in /usr/local/mavergreen/recaulk were updated."
  RELAUNCH_MARKER "/tmp/.mavergreen-recaulk-updater-relaunched"
)
