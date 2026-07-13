/// Kill switches for features that are fully built and tested but not yet
/// ready to ship to real users. Flip to `true` and rebuild to turn a
/// feature back on — no other code changes needed.
///
/// kEnableMcpConnector: the in-app HTTP bridge + Settings UI that lets a
/// local MCP server (mcp-server/) read/manage tasks for Claude Desktop/Code.
/// Off because it opens a network-reachable endpoint on the phone and hasn't
/// been through a real-world security/usability pass yet.
const bool kEnableMcpConnector = false;

/// kEnableGoogleCalendar: Google sign-in + Calendar event import (Settings
/// UI, todo/week screen event rows). Off because
/// GoogleCalendarService._serverClientId still needs a real Google Cloud
/// Console OAuth client before it can do anything.
const bool kEnableGoogleCalendar = false;
