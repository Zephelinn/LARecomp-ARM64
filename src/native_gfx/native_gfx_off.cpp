// android: the Native Graphics Runtime (src/native_gfx) and the probe are D3D12-only and are not built outside
// Windows (CMakeLists.txt). The game draws through the SDK's Xenos GPU plugin, which is what Windows does too
// unless mcla_native_gfx / mcla_native_gfx_nocp are set. This file is what the rest of the app calls instead:
// the no-command-processor mode is never wanted, and the cvars the app reads exist and stay false.
#ifndef REXGLUE_HAS_XEO3_TARGET

#include <cstdint>
#include <memory>

#include <rex/cvar.h>
#include <rex/graphics/pipeline/texture/util.h>
#include <rex/ui/overlay/debug_overlay.h>  // rex::ui::FrameStats

#include "native_gfx/guest/texture_format.h"
#include "native_gfx/native_gfx.h"
#include "native_gfx/nocp/nocp_app.h"

REXCVAR_DEFINE_BOOL(mcla_native_gfx, false, "MCLA/NativeGfx",
                    "Native Graphics Runtime (D3D12 only; not available in this build)");
REXCVAR_DEFINE_BOOL(mcla_native_gfx_own_device, false, "MCLA/NativeGfx",
                    "Native Graphics Runtime device (D3D12 only; not available in this build)");
REXCVAR_DEFINE_BOOL(mcla_native_gfx_own_swapchain, false, "MCLA/NativeGfx",
                    "Native Graphics Runtime swap chain (D3D12 only; not available in this build)");

namespace mcla::native_gfx {

bool Active() { return false; }

// Same as texture_format.cpp: the SDK's Xenos swizzle with the pitch aligned to a 32-block tile.
uint32_t TiledOffset2D(uint32_t x_block, uint32_t y_block, uint32_t width_blocks, uint32_t bytes_per_block) {
  uint32_t bpb_log2 = 0;
  while ((2u << bpb_log2) <= bytes_per_block) {
    ++bpb_log2;
  }
  return uint32_t(rex::graphics::texture_util::GetTiledOffset2D(int32_t(x_block), int32_t(y_block), width_blocks,
                                                                bpb_log2));
}

}  // namespace mcla::native_gfx

namespace mcla::native_gfx::nocp {

bool WantNoCommandProcessor() { return false; }
std::unique_ptr<rex::ui::ImmediateDrawer> CreateImmediateDrawer() { return nullptr; }
bool AttachPresentation(rex::ui::Window*, rex::ui::ImGuiDrawer*, rex::ui::ImmediateDrawer*) { return false; }
bool InstallGuestGpu() { return false; }
void NoteHook(const char*) {}
void NoteFrameEnd() {}
void NoteSwapCall() {}
rex::ui::FrameStats GuestFrameStats() { return {}; }
rex::ui::d3d12::D3D12Provider* Provider() { return nullptr; }
rex::ui::Presenter* PresenterPtr() { return nullptr; }
const char* LastHookName() { return nullptr; }
uint64_t HookCallCount() { return 0; }
uint64_t FrameEndCount() { return 0; }
uint64_t SwapCount() { return 0; }

}  // namespace mcla::native_gfx::nocp

#endif  // REXGLUE_HAS_XEO3_TARGET
