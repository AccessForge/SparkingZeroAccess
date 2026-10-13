param([string]$LuaSource = (Join-Path $PSScriptRoot '..\speech_bridge\lua-5.4.7\src'))
$ErrorActionPreference = 'Stop'
$LuaSource = (Resolve-Path -LiteralPath $LuaSource).Path
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath (Join-Path $LuaSource 'lua.h'))) { throw 'Lua 5.4.7 source is required.' }
$sources = @(Get-ChildItem -LiteralPath $LuaSource -Filter '*.c' | Where-Object { $_.Name -notin @('lua.c','luac.c') })
$items = @('<ClCompile Include="audio_bridge.c" />')
$items += $sources | ForEach-Object { '<ClCompile Include="' + [System.Security.SecurityElement]::Escape($_.FullName) + '" />' }
$template = @'
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations"><ProjectConfiguration Include="Release|x64"><Configuration>Release</Configuration><Platform>x64</Platform></ProjectConfiguration></ItemGroup>
  <PropertyGroup Label="Globals"><ProjectGuid>{5BFE9281-D559-4AB3-9CD4-2D5578D46CFA}</ProjectGuid><WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion></PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
  <PropertyGroup Label="Configuration"><ConfigurationType>DynamicLibrary</ConfigurationType><PlatformToolset>v143</PlatformToolset><UseDebugLibraries>false</UseDebugLibraries><CharacterSet>Unicode</CharacterSet></PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
  <PropertyGroup><OutDir>$(MSBuildThisFileDirectory)bin\</OutDir><IntDir>$(MSBuildThisFileDirectory)obj\</IntDir><TargetName>audio_bridge</TargetName></PropertyGroup>
  <ItemDefinitionGroup><ClCompile><AdditionalIncludeDirectories>__LUA__;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories><RuntimeLibrary>MultiThreaded</RuntimeLibrary><WarningLevel>Level3</WarningLevel><Optimization>MaxSpeed</Optimization><LanguageStandard_C>stdc17</LanguageStandard_C><PreprocessorDefinitions>_CRT_SECURE_NO_WARNINGS;NDEBUG;%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile><Link><AdditionalDependencies>winmm.lib;%(AdditionalDependencies)</AdditionalDependencies><AdditionalOptions>/PDBALTPATH:audio_bridge.pdb %(AdditionalOptions)</AdditionalOptions></Link></ItemDefinitionGroup>
  <ItemGroup>__ITEMS__</ItemGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
</Project>
'@
$project = $template.Replace('__LUA__', [System.Security.SecurityElement]::Escape($LuaSource)).Replace('__ITEMS__', ($items -join "`n"))
$projectPath = Join-Path $PSScriptRoot 'audio_bridge.vcxproj'
Set-Content -LiteralPath $projectPath -Value $project -Encoding UTF8
& $msbuild $projectPath /p:Configuration=Release /p:Platform=x64 /nologo /v:minimal
if ($LASTEXITCODE -ne 0) { throw 'Native audio module build failed.' }
