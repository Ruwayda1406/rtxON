@echo off

setlocal
set GLSL_COMPILER=glslangValidator.exe
set SOURCE_FOLDER="./../src/shaders/"
set BINARIES_FOLDER="./shaders/"

:: raygen shaders
%GLSL_COMPILER% --target-env vulkan1.2 -V -S rgen %SOURCE_FOLDER%ray_gen.glsl -o %BINARIES_FOLDER%ray_gen.bin

:: closest-hit shaders
%GLSL_COMPILER% --target-env vulkan1.2 -V -S rchit %SOURCE_FOLDER%ray_chit.glsl -o %BINARIES_FOLDER%ray_chit.bin

:: any-hit shaders
%GLSL_COMPILER% --target-env vulkan1.2 -V -S rchit %SOURCE_FOLDER%ray_anyhit.glsl -o %BINARIES_FOLDER%ray_anyhit.bin

:: miss shaders
%GLSL_COMPILER% --target-env vulkan1.2 -V -S rmiss %SOURCE_FOLDER%ray_miss.glsl -o %BINARIES_FOLDER%ray_miss.bin

pause
