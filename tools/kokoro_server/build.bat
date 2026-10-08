@echo off
rem Builds kokoro-server.exe for Windows x64 against sherpa-onnx's C API.
rem
rem   build.bat <unpacked sherpa-onnx-v1.13.8-win-x64-shared-MD-Release folder>
rem
rem Needs Visual Studio 2022 with the C++ tools. The result goes to bin\windows\, which the duck
rem copies next to sherpa-onnx-c-api.dll when it installs the natural voices.
setlocal
set SHERPA=%~1
if "%SHERPA%"=="" (
  echo usage: build.bat ^<sherpa-onnx win-x64 shared folder^>
  exit /b 2
)
rem The brackets in "Program Files (x86)" would end the for loop's own, so the path goes in a variable.
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do set VS=%%i
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set OUT=%~dp0..\..\bin\windows
if not exist "%OUT%" mkdir "%OUT%"
cl /nologo /O2 /MD /W3 /I "%SHERPA%\include" "%~dp0kokoro_server.c" /Fe"%OUT%\kokoro-server.exe" /Fo"%TEMP%\kokoro_server.obj" /link "%SHERPA%\lib\sherpa-onnx-c-api.lib"
