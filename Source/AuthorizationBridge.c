#include <Security/Authorization.h>

// Swift marks this legacy API unavailable even though macOS keeps it for
// compatibility. Keep the bridge deliberately tiny: validation and the fixed
// pmset allow-list live in Swift, and no shell or arbitrary path is exposed.
OSStatus TSAuthorizationExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *pathToTool,
    AuthorizationFlags options,
    char * const *arguments,
    FILE **communicationsPipe
) {
    return AuthorizationExecuteWithPrivileges(
        authorization,
        pathToTool,
        options,
        arguments,
        communicationsPipe
    );
}
