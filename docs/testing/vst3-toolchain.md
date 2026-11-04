# VST 3 toolchain feasibility

November 4, 2026 local automated check only. No Covoo plug-in, phone transport,
Live session, audio endpoint or latency was tested. This stock SDK check does not
close a milestone acceptance gate. Nothing was installed into plug-in folders.

## Pinned sources

Upstream https://github.com/steinbergmedia/vst3sdk.git, tag v3.8.1_build_84:

| Repository | Commit |
| --- | --- |
| vst3sdk | 3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96 |
| base | fcf9da0bd27a16f7f03773a3a39822f28f5c8477 |
| cmake | 054c9143cbb8d47fc4694e473f2ee3b4d951a8f5 |
| pluginterfaces | 4f547e8e102b47de4a8b8aaf343c73b700786372 |
| public.sdk | 586dc5e6c8012c3e4b01c79389375cbe96bdb1da |

Only these four submodules were initialized. The SDK's MIT license remains in
the checkout; SDK code/binaries are not committed or packaged with Covoo. Future
distribution requires retaining notices and reviewing branding requirements.

## Reproduction

Use a separate ignored checkout/build directory. The commands below describe the
local proof with VS Build Tools 2026 18.6, MSVC 19.51.36244, SDK 10.0.26100.0 and
bundled CMake 4.2.3. They download pinned user-mode SDK sources, not drivers.
No CMake install target or audio host is run.

```powershell
git clone --no-checkout https://github.com/steinbergmedia/vst3sdk.git .tools/vst3sdk-feasibility
git -C .tools/vst3sdk-feasibility checkout --detach 3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96
git -C .tools/vst3sdk-feasibility submodule update --init --depth 1 base cmake pluginterfaces public.sdk
$vstCmake = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $vstCmake -S .tools/vst3sdk-feasibility -B build/vst3-toolchain-feasibility `
    -G 'Visual Studio 18 2026' -A x64 `
    -DSMTG_CREATE_PLUGIN_LINK=OFF -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF `
    -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=OFF -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=ON `
    -DSMTG_DISABLE_CODE_SIGNING=ON -DSMTG_RUN_VST_VALIDATOR=ON
& $vstCmake --build build/vst3-toolchain-feasibility --config Release --target adelay --parallel 4
```

Stop if a command fails. Configuration includes non-GUI sample targets, but only
ADelay and its SDK/module-info/validator dependencies are built. Plug-in linking
must remain OFF: the SDK's default can create links in installed plug-in folders.
No ASIO SDK or hardware audio host is needed for this check.

## Observed result

Release x64 build exited 0. Validator self-test succeeded and ADelay validation
reported **57 tests passed, 0 failed**. CMakeCache confirms plugin-link, VSTGUI
and hosting-example options OFF. The bundle is isolated under
build/vst3-toolchain-feasibility/VST3/Release/adelay.vst3; it is an upstream delay
effect, not a Covoo receiver. Local output is build/vst3-toolchain-build.log.

Covoo's IPC authentication, queue/clock behavior, real-time safety, instrument
processing in Live and measured effects latency still require implementation
and separate validation. Physical comparisons remain deferred in todo.md.
