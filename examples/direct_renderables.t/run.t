Direct retained renderables
===========================

The direct path keeps the same typed renderables while changing their state:

  $ ../direct_renderables.exe
  identities: panel=1 status=2
  initial:
  ┌────────────┐
  │ initial    │
  └────────────┘
  after text update:
  ┌────────────┐
  │ updated    │
  └────────────┘
  after box update:
  ╔════════════╗
  ║ updated    ║
  ╚════════════╝
