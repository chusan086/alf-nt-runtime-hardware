# Architecture

The shared core receives a complete operation through a 32-bit ready/valid
request stream and returns five 32-bit response words. Runtime parameters are
validated once, converted to a registered operation descriptor, and consumed
by local controller, key/tweak, round, and key-bank services. The design
time-multiplexes one AES round lane across the operation phases.

The final FPGA key bank uses inferred synchronous RAM. M1 and M4 keep the same
AES lane, controller/service boundaries, key-bank interface, reset semantics,
and streaming protocol, while replacing runtime parameter selection with one
static parameter point. This is the accepted same-source comparison boundary.

The release is family-bounded. It does not claim a universal shared-hardware
method for unrelated cryptographic families.

For Chinese documentation, see [ARCHITECTURE-CN.md](ARCHITECTURE-CN.md).
