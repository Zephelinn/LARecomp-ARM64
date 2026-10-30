package org.larecomp.android;

import android.os.Bundle;
import android.view.WindowManager;

import org.libsdl.app.SDLActivity;

/**
 * SDL3's activity with LARecomp's libraries. SDL3 itself is linked statically into the ReXGlue runtime
 * (librexruntime*.so, which holds SDL's JNI_OnLoad), so there is no libSDL3.so; libmain.so is the game and its
 * SDL_main the entry point. The GPU plugin (librexgpu-xenos*.so) is loaded by the runtime itself, by name.
 */
public class LarecompActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "c++_shared", BuildConfigNames.RUNTIME, "main" };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // a race with no touch input must not let the screen time out
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
}
