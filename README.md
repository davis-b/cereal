_cereal_ is a network serialization library written in and for Zig. It handles converting data to and from net-endian format. _cereal_ also ensures types are represented in a standard number of bytes when sent over the wire, regardless of how many bytes are used to represent that type on each local machine.

_cereal_ is known to work on x86_64 Linux and Windows. It is likely to work with a broader set of targets.

_cereal_ is built for Zig version 0.8.