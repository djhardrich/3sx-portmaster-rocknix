#include "port/paths.h"

#include <SDL3/SDL.h>

#include <stdlib.h>

static const char* pref_path = NULL;

const char* Paths_GetPrefPath() {
    if (pref_path != NULL) {
        return pref_path;
    }

#if CRS_PLATFORM_PORTMASTER
    // The PortMaster launcher sets XDG_DATA_HOME to the per-port conf
    // directory (e.g. /roms/ports/3sx/conf). We use that directly without
    // the "CrowdedStreet/3SX" nesting that SDL_GetPrefPath would apply.
    const char* xdg = SDL_getenv("XDG_DATA_HOME");

    if (xdg != NULL && xdg[0] != '\0') {
        // Ensure trailing slash for downstream string concatenation.
        const size_t len = SDL_strlen(xdg);
        const bool needs_slash = (xdg[len - 1] != '/');
        char* buf = NULL;
        SDL_asprintf(&buf, "%s%s", xdg, needs_slash ? "/" : "");
        pref_path = buf;
    } else {
        pref_path = SDL_strdup("/tmp/3sx/");
    }
#else
    pref_path = SDL_GetPrefPath("CrowdedStreet", "3SX");
#endif

    return pref_path;
}

const char* Paths_GetBasePath() {
    return SDL_GetBasePath();
}
