// A higher-resolution animated kamisama overlay for Ghostty.
//
// The 256x384 mask is extracted from dark-line intensity rather than alpha,
// keeping the white robe hollow while retaining fine hand-drawn hatching.
// Each row uses ten positive 28-bit words for portable bit operations.

const int MASK_WIDTH = 256;
const int MASK_HEIGHT = 384;
const int MASK_WORD_BITS = 28;
const int MASK_WORDS_PER_ROW = 10;

const int kamisama2Mask[3840] = int[3840](
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 3584, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 6912, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 5888, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 66985728, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 267378176, 1, 0, 0, 0, 0,
    0, 0, 0, 0, 268040192, 24579, 0, 0, 0, 0,
    0, 0, 0, 0, 31356928, 28678, 0, 0, 0, 0,
    0, 0, 0, 0, 50449920, 64524, 0, 0, 0, 0,
    0, 0, 0, 0, 167802624, 65532, 0, 0, 0, 0,
    0, 0, 0, 0, 100694912, 28927, 0, 0, 0, 0,
    0, 0, 0, 0, 234884288, 8291, 0, 0, 0, 0,
    0, 0, 0, 0, 226591424, 99, 0, 0, 0, 0,
    0, 0, 0, 0, 166789472, 194, 0, 0, 0, 0,
    0, 0, 0, 0, 138084528, 194, 0, 0, 0, 0,
    0, 0, 0, 0, 136118520, 386, 0, 0, 0, 0,
    0, 0, 0, 0, 134676600, 390, 0, 0, 0, 0,
    0, 0, 0, 0, 376956, 387, 0, 0, 0, 0,
    0, 0, 0, 0, 27774, 898, 0, 0, 0, 0,
    0, 0, 0, 0, 6750, 770, 0, 0, 0, 0,
    0, 0, 0, 0, 3286, 786, 0, 0, 0, 0,
    0, 0, 0, 0, 134219766, 234430, 0, 0, 0, 0,
    0, 0, 0, 0, 134218678, 524278, 0, 0, 0, 0,
    0, 0, 0, 0, 264241662, 524287, 0, 0, 0, 0,
    0, 0, 0, 0, 167511022, 197531, 0, 0, 0, 0,
    0, 0, 0, 0, 152012766, 411, 0, 0, 0, 0,
    0, 0, 0, 0, 100793754, 473, 0, 0, 0, 0,
    0, 0, 0, 0, 234913304, 193, 0, 0, 0, 0,
    0, 0, 0, 0, 238550580, 109, 0, 0, 0, 0,
    0, 0, 0, 33554432, 201325416, 119, 0, 0, 0, 0,
    0, 0, 0, 33554432, 259797240, 31, 0, 0, 0, 0,
    0, 0, 0, 33554432, 218128600, 47, 0, 0, 0, 0,
    0, 0, 0, 67108864, 47153468, 30, 0, 0, 0, 0,
    0, 0, 0, 134217728, 58393156, 14, 0, 0, 0, 0,
    0, 0, 0, 201326592, 134094215, 31, 0, 0, 0, 0,
    0, 0, 0, 134217728, 267383555, 25, 0, 0, 0, 0,
    0, 0, 0, 0, 268179471, 16, 0, 0, 0, 0,
    0, 0, 0, 0, 218103800, 32, 0, 0, 0, 0,
    0, 0, 0, 0, 138407872, 64, 0, 0, 0, 0,
    0, 0, 0, 0, 205389824, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 209453056, 192, 0, 0, 0, 0,
    0, 0, 0, 0, 104726528, 1984, 0, 0, 0, 0,
    0, 0, 0, 0, 57933824, 1472, 0, 0, 0, 0,
    0, 0, 0, 0, 33488896, 960, 0, 0, 0, 0,
    0, 0, 0, 0, 67051008, 384, 0, 0, 0, 0,
    0, 0, 0, 0, 214826976, 3, 0, 0, 0, 0,
    0, 0, 0, 0, 268435312, 6, 0, 0, 0, 0,
    0, 0, 0, 0, 268435420, 5, 0, 0, 0, 0,
    0, 0, 0, 0, 268435447, 63, 0, 0, 0, 0,
    0, 0, 0, 201326592, 268435453, 127, 0, 0, 0, 0,
    0, 0, 0, 234881024, 268435455, 255, 0, 0, 0, 0,
    0, 0, 0, 234881024, 268435455, 1987, 0, 0, 0, 0,
    0, 0, 0, 239075328, 134217727, 1982, 0, 0, 0, 0,
    0, 0, 0, 251658240, 260046847, 3695, 0, 0, 0, 0,
    0, 0, 0, 260046848, 268434943, 2043, 0, 0, 0, 0,
    0, 0, 0, 264241152, 49938431, 8191, 0, 0, 0, 0,
    0, 0, 0, 266862592, 255803391, 7247, 0, 0, 0, 0,
    0, 0, 0, 267386880, 266861045, 16376, 0, 0, 0, 0,
    0, 0, 0, 66060288, 150732799, 21503, 0, 0, 0, 0,
    0, 0, 0, 234356736, 207568863, 13183, 0, 0, 0, 0,
    0, 0, 0, 267911168, 264478713, 13281, 0, 0, 0, 0,
    0, 0, 0, 201129984, 63108926, 41211, 0, 0, 0, 0,
    0, 0, 0, 251396096, 16137183, 59294, 0, 0, 0, 0,
    0, 0, 0, 268304384, 27148287, 124870, 0, 0, 0, 0,
    0, 0, 0, 268369920, 25585532, 115660, 0, 0, 0, 0,
    0, 0, 0, 218071040, 17195903, 115468, 0, 0, 0, 0,
    0, 0, 0, 259424256, 50619289, 116248, 0, 0, 0, 0,
    0, 0, 0, 133070848, 51143646, 115736, 0, 0, 0, 0,
    0, 0, 0, 218071040, 34390907, 232496, 0, 0, 0, 0,
    0, 0, 0, 242024448, 101499705, 232496, 0, 0, 0, 0,
    0, 0, 0, 267190272, 101499704, 170080, 0, 0, 0, 0,
    0, 0, 0, 233635840, 202998296, 430176, 0, 0, 0, 0,
    0, 0, 0, 107020288, 202999320, 323776, 0, 0, 0, 0,
    0, 0, 0, 123797504, 202999324, 848064, 0, 0, 0, 0,
    0, 0, 0, 132317184, 135988764, 909697, 0, 0, 0, 0,
    0, 0, 0, 117112832, 137561624, 901505, 0, 0, 0, 0,
    0, 0, 0, 133890048, 137561624, 901377, 0, 0, 0, 0,
    0, 0, 0, 133890048, 3539984, 1950467, 0, 0, 0, 0,
    0, 0, 0, 106561536, 3542064, 2998784, 0, 0, 0, 0,
    0, 0, 0, 106823680, 2493488, 2940928, 0, 0, 0, 0,
    0, 0, 0, 106823680, 265264, 2940928, 0, 0, 0, 0,
    0, 0, 0, 115212288, 0, 7102464, 0, 0, 0, 0,
    0, 0, 0, 117178368, 0, 4874240, 0, 0, 0, 0,
    0, 0, 0, 83623936, 0, 9330800, 0, 0, 0, 0,
    0, 0, 0, 16646144, 0, 25878768, 0, 0, 0, 0,
    0, 0, 0, 16515072, 15, 1765616, 0, 0, 0, 0,
    0, 0, 0, 15990784, 15, 1814528, 0, 0, 0, 0,
    0, 0, 0, 15990784, 15, 1683456, 0, 0, 0, 0,
    0, 0, 0, 14942208, 0, 1153024, 0, 0, 0, 0,
    0, 0, 0, 31457280, 0, 104448, 0, 0, 0, 0,
    0, 0, 0, 31719424, 0, 101376, 0, 0, 0, 0,
    0, 0, 0, 53215232, 0, 3584, 0, 0, 0, 0,
    0, 0, 0, 260833280, 0, 6656, 0, 0, 0, 0,
    0, 0, 0, 227016704, 917505, 13184, 0, 0, 0, 0,
    0, 0, 0, 160956416, 917507, 59328, 0, 0, 0, 0,
    0, 0, 0, 101187584, 917519, 36464, 0, 0, 0, 0,
    0, 0, 0, 186122240, 31, 202812, 0, 0, 0, 0,
    0, 0, 0, 228065280, 201326841, 397431, 0, 0, 0, 0,
    0, 0, 0, 213909504, 267390924, 811168, 0, 0, 0, 0,
    0, 0, 0, 106954752, 67107942, 7397696, 0, 0, 0, 0,
    0, 0, 0, 36700160, 67100771, 14729856, 0, 0, 0, 0,
    0, 0, 0, 160432128, 67100720, 25265920, 0, 0, 0, 0,
    0, 0, 0, 8912896, 268427313, 58852096, 0, 0, 0, 0,
    0, 0, 0, 262144, 251654160, 50594307, 0, 0, 0, 0,
    0, 0, 0, 196608, 266007576, 202118662, 0, 0, 0, 0,
    0, 0, 0, 65536, 117125656, 202114054, 0, 0, 0, 0,
    0, 0, 0, 68255744, 129561112, 1583108, 0, 0, 0, 0,
    0, 0, 0, 540672, 33538828, 3164164, 0, 0, 0, 0,
    0, 0, 0, 286720, 16773388, 3166220, 0, 0, 0, 0,
    0, 0, 0, 21245952, 16514318, 36876, 0, 0, 0, 0,
    0, 0, 0, 4198400, 16383238, 40968, 0, 0, 0, 0,
    0, 0, 0, 10485760, 16383238, 122888, 0, 0, 0, 0,
    0, 0, 0, 2129920, 28900742, 49160, 0, 0, 0, 0,
    0, 0, 0, 5242880, 28899718, 24, 0, 0, 0, 0,
    0, 0, 0, 4218880, 28867715, 24, 0, 0, 0, 0,
    0, 0, 0, 3145728, 28851331, 24, 0, 0, 0, 0,
    0, 0, 0, 3145728, 28851328, 16, 0, 0, 0, 0,
    0, 0, 0, 0, 28851392, 16, 0, 0, 0, 0,
    0, 0, 0, 0, 28851392, 16, 0, 0, 0, 0,
    0, 0, 0, 0, 28843072, 48, 0, 0, 0, 0,
    0, 0, 0, 0, 28843072, 48, 0, 0, 0, 0,
    0, 0, 0, 0, 28843072, 32, 0, 0, 0, 0,
    0, 0, 0, 0, 28843104, 32, 0, 0, 0, 0,
    0, 0, 0, 0, 28843552, 32, 0, 0, 0, 0,
    0, 0, 0, 0, 28839456, 96, 0, 0, 0, 0,
    0, 0, 0, 0, 28839712, 96, 0, 0, 0, 0,
    0, 0, 0, 0, 28839728, 65, 0, 0, 0, 0,
    0, 0, 0, 0, 20451248, 64, 0, 0, 0, 0,
    0, 0, 0, 0, 20451216, 64, 0, 0, 0, 0,
    0, 0, 0, 0, 20451216, 192, 0, 0, 0, 0,
    0, 0, 0, 0, 20451088, 192, 0, 0, 0, 0,
    0, 0, 0, 0, 54005264, 192, 0, 0, 0, 0,
    0, 0, 0, 0, 51908376, 128, 0, 0, 0, 0,
    0, 0, 0, 0, 50333592, 128, 0, 0, 0, 0,
    0, 0, 0, 0, 50333576, 128, 0, 0, 0, 0,
    0, 0, 0, 0, 50333576, 128, 0, 0, 0, 0,
    0, 0, 0, 0, 50333576, 384, 0, 0, 0, 0,
    0, 0, 0, 0, 50333576, 384, 0, 0, 0, 0,
    0, 0, 0, 0, 117442508, 384, 0, 0, 0, 0,
    0, 0, 0, 0, 100665292, 256, 0, 0, 0, 0,
    0, 0, 0, 0, 1988, 256, 0, 0, 0, 0,
    0, 0, 0, 0, 900, 256, 0, 0, 0, 0,
    0, 0, 0, 0, 900, 256, 0, 0, 0, 0,
    0, 0, 0, 0, 900, 768, 0, 0, 0, 0,
    0, 0, 0, 0, 902, 768, 0, 0, 0, 0,
    0, 0, 0, 0, 962, 768, 0, 0, 0, 0,
    0, 0, 0, 0, 194, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 194, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 227, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 227, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 241, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 241, 512, 0, 0, 0, 0,
    0, 0, 0, 0, 241, 1536, 0, 0, 0, 0,
    0, 0, 0, 0, 225, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 241, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 225, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 225, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 225, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 241, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 112, 1536, 0, 0, 0, 0,
    0, 0, 0, 134217728, 112, 1024, 0, 0, 0, 0,
    0, 0, 0, 134217728, 96, 1024, 0, 0, 0, 0,
    0, 0, 0, 134217728, 96, 1024, 0, 0, 0, 0,
    0, 0, 0, 134217728, 96, 1024, 0, 0, 0, 0,
    0, 0, 0, 201326592, 96, 1024, 0, 0, 0, 0,
    0, 0, 0, 201326592, 112, 1024, 0, 0, 0, 0,
    0, 0, 0, 67108864, 112, 1024, 0, 0, 0, 0,
    0, 0, 0, 67108864, 120, 1024, 0, 0, 0, 0,
    0, 0, 0, 67108864, 120, 3072, 0, 0, 0, 0,
    0, 0, 0, 67108864, 112, 3072, 0, 0, 0, 0,
    0, 0, 0, 67108864, 48, 3072, 0, 0, 0, 0,
    0, 0, 0, 100663296, 48, 3072, 0, 0, 0, 0,
    0, 0, 0, 100663296, 48, 3072, 0, 0, 0, 0,
    0, 0, 0, 100663296, 48, 2048, 0, 0, 0, 0,
    0, 0, 0, 100663296, 48, 2048, 0, 0, 0, 0,
    0, 0, 0, 33554432, 48, 2048, 0, 0, 0, 0,
    0, 0, 0, 33554432, 48, 2048, 0, 0, 0, 0,
    0, 0, 0, 33554432, 48, 6144, 0, 0, 0, 0,
    0, 0, 0, 33554432, 48, 6144, 0, 0, 0, 0,
    0, 0, 0, 33554432, 48, 6144, 0, 0, 0, 0,
    0, 0, 0, 33554432, 16, 6144, 0, 0, 0, 0,
    0, 0, 0, 33554432, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 33554432, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 33554432, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 50331648, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 50331648, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 50331648, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 50331648, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 16777216, 0, 4096, 0, 0, 0, 0,
    0, 0, 0, 16777216, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 16777216, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 16777216, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 16777216, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 25165824, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 25165824, 0, 12288, 0, 0, 0, 0,
    0, 0, 0, 25165824, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 25165824, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 25165824, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 8192, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 24576, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 24576, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 24576, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 24576, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 24576, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 8388608, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 12582912, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 12582912, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 12582912, 0, 16384, 0, 0, 0, 0,
    0, 0, 0, 12582912, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 12582912, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 49152, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 4194304, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 6291456, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 6291456, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 6291456, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 2097152, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 2097152, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 2097152, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 2097152, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 2097152, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 3145728, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 3145728, 0, 32768, 0, 0, 0, 0,
    0, 0, 0, 3145728, 0, 98304, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 98304, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 98304, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 98304, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 98304, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 1048576, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 1572864, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 1572864, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 1572864, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 524288, 0, 65536, 0, 0, 0, 0,
    0, 0, 0, 524288, 3145728, 65536, 0, 0, 0, 0,
    0, 0, 0, 524288, 2097152, 196608, 0, 0, 0, 0,
    0, 0, 0, 524288, 6291456, 196608, 0, 0, 0, 0,
    0, 0, 0, 524288, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 524288, 2097152, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 2097152, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 8388608, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 29360128, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 29360128, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 29360128, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 25165824, 196608, 0, 0, 0, 0,
    0, 0, 0, 262144, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 6553600, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 6553600, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 3407872, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 3407872, 12582912, 196608, 0, 0, 0, 0,
    0, 0, 0, 1310720, 25165824, 196608, 0, 0, 0, 0,
    0, 0, 0, 1966080, 16777216, 196608, 0, 0, 0, 0,
    0, 0, 0, 1966080, 50331648, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 16777408, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 16777600, 196608, 0, 0, 0, 0,
    0, 0, 0, 786432, 16777984, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 1536, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 1088, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 192, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 384, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 16777984, 196608, 0, 0, 0, 0,
    0, 0, 0, 393216, 50333184, 196608, 0, 0, 0, 0,
    0, 0, 0, 458752, 50331648, 196608, 0, 0, 0, 0,
    0, 0, 0, 983040, 50331888, 196608, 0, 0, 0, 0,
    0, 0, 0, 65536, 992, 196608, 0, 0, 0, 0,
    0, 0, 0, 65536, 1792, 196608, 0, 0, 0, 0,
    0, 0, 0, 65536, 0, 196608, 0, 0, 0, 0,
    0, 0, 0, 65536, 384, 196608, 0, 0, 0, 0,
    0, 0, 0, 65536, 384, 196612, 0, 0, 0, 0,
    0, 0, 0, 98304, 504, 196615, 0, 0, 0, 0,
    0, 0, 0, 32768, 201327608, 196609, 0, 0, 0, 0,
    0, 0, 0, 32768, 234881792, 196639, 0, 0, 0, 0,
    0, 0, 0, 32768, 0, 196671, 0, 0, 0, 0,
    0, 0, 0, 32768, 32, 196608, 0, 0, 0, 0,
    0, 0, 0, 32768, 1008, 196608, 0, 0, 0, 0,
    0, 0, 0, 32768, 132121472, 196608, 0, 0, 0, 0,
    0, 0, 0, 49152, 264241152, 196615, 0, 0, 0, 0,
    0, 0, 0, 49152, 992, 196612, 0, 0, 0, 0,
    0, 0, 0, 16384, 65012216, 196608, 0, 0, 0, 0,
    0, 0, 0, 16384, 266338416, 196615, 0, 0, 0, 0,
    0, 0, 0, 16384, 134218220, 196615, 0, 0, 0, 0,
    0, 0, 0, 16384, 4092, 196608, 0, 0, 0, 0,
    0, 0, 0, 16384, 3980, 196623, 0, 0, 0, 0,
    0, 0, 0, 16384, 234885118, 131079, 0, 0, 0, 0,
    0, 0, 0, 16384, 264249342, 131072, 0, 0, 0, 0,
    0, 0, 0, 16384, 12583166, 131072, 0, 0, 0, 0,
    0, 0, 0, 24576, 264242118, 131087, 0, 0, 0, 0,
    0, 0, 0, 24576, 264245247, 131327, 0, 0, 0, 0,
    0, 0, 0, 24576, 8190, 393440, 0, 0, 0, 0,
    0, 0, 0, 24576, 133693682, 393468, 0, 0, 0, 0,
    0, 0, 0, 24576, 267387119, 393247, 0, 0, 0, 0,
    0, 0, 0, 134225920, 2047, 393343, 0, 0, 0, 0,
    0, 0, 0, 8192, 1123, 393280, 0, 0, 0, 0,
    0, 0, 0, 8192, 6291555, 393336, 0, 0, 0, 0,
    0, 0, 0, 234889216, 267912191, 393279, 0, 0, 0, 0,
    0, 0, 0, 234889216, 260047871, 262175, 0, 0, 0, 0,
    0, 0, 0, 12288, 201326689, 262175, 0, 0, 0, 0,
    0, 0, 0, 251670528, 201326719, 262207, 0, 0, 0, 0,
    0, 0, 0, 251670528, 31719423, 262144, 0, 0, 0, 0,
    0, 0, 0, 12288, 268435233, 262147, 0, 0, 0, 0,
    0, 0, 0, 260059136, 208666671, 262207, 0, 0, 0, 0,
    0, 0, 0, 260059136, 1023, 262264, 0, 0, 0, 0,
    0, 0, 0, 134221824, 24961, 262240, 0, 0, 0, 0,
    0, 0, 0, 260050944, 2089023, 786558, 0, 0, 0, 0,
    0, 0, 0, 251662336, 268410879, 786447, 0, 0, 0, 0,
    0, 0, 0, 134221824, 260054016, 786495, 0, 0, 0, 0,
    0, 0, 0, 134221824, 260046904, 524799, 0, 0, 0, 0,
    0, 0, 0, 201330688, 159383583, 524799, 0, 0, 0, 0,
    0, 0, 0, 201330688, 234881151, 525311, 0, 0, 0, 0,
    0, 0, 0, 234885120, 264243192, 525183, 0, 0, 0, 0,
    0, 0, 0, 234887168, 62918401, 1572927, 0, 0, 0, 0,
    0, 0, 0, 264243200, 263196671, 1573887, 0, 0, 0, 0,
    0, 0, 0, 264243200, 259000319, 1576959, 0, 0, 0, 0,
    0, 0, 0, 201328640, 264257287, 1580047, 0, 0, 0, 0,
    0, 0, 0, 266340352, 251662343, 1573887, 0, 0, 0, 0,
    0, 0, 0, 266340352, 255852543, 1056763, 0, 0, 0, 0,
    0, 0, 0, 260048896, 268435393, 1055775, 0, 0, 0, 0,
    0, 0, 0, 266340352, 117469191, 1049086, 0, 0, 0, 0,
    0, 0, 0, 266341376, 252705791, 1052608, 0, 0, 0, 0,
    0, 0, 0, 264242176, 268404679, 3148815, 0, 0, 0, 0,
    0, 0, 0, 266339328, 266338559, 3146239, 0, 0, 0, 0,
    0, 0, 0, 200803328, 268177407, 3149823, 0, 0, 0, 0,
    0, 0, 0, 238552064, 33504769, 2104860, 0, 0, 0, 0,
    0, 0, 0, 267387904, 267915391, 3151871, 0, 0, 0, 0,
    0, 0, 0, 267387904, 134221823, 3147775, 0, 0, 0, 0,
    0, 0, 0, 202899968, 267452161, 3162111, 0, 0, 0, 0,
    0, 0, 0, 268173824, 268434959, 3174431, 0, 0, 0, 0,
    0, 0, 0, 267911680, 268305407, 2101247, 0, 0, 0, 0,
    0, 0, 0, 257950208, 264257528, 2129919, 0, 0, 0, 0,
    0, 0, 0, 267387392, 268433663, 2113280, 0, 0, 0, 0,
    0, 0, 0, 267387648, 268419583, 6422527, 0, 0, 0, 0,
    0, 0, 0, 254804736, 267585535, 6537223, 0, 0, 0, 0,
    0, 0, 0, 267387648, 268435455, 6307839, 0, 0, 0, 0,
    0, 0, 0, 267911936, 268427519, 6324223, 0, 0, 0, 0,
    0, 0, 0, 236716800, 66854911, 6552576, 0, 0, 0, 0,
    0, 0, 0, 267911680, 268435455, 4268031, 0, 0, 0, 0,
    0, 0, 0, 268176384, 268419103, 7372799, 0, 0, 0, 0,
    0, 0, 0, 263991296, 134217727, 1898496, 0, 0, 0, 0,
    0, 0, 0, 268025856, 16777215, 475120, 0, 0, 0, 0,
    0, 0, 0, 265224192, 268435455, 123391, 0, 0, 0, 0,
    0, 0, 0, 267911168, 268435455, 16383, 0, 0, 0, 0,
    0, 0, 0, 264241152, 268435455, 255, 0, 0, 0, 0,
    0, 0, 0, 201326592, 268435455, 7, 0, 0, 0, 0,
    0, 0, 0, 0, 268435424, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0
);

float maskPixel(ivec2 pixel) {
    if (pixel.x < 0 || pixel.x >= MASK_WIDTH ||
        pixel.y < 0 || pixel.y >= MASK_HEIGHT) {
        return 0.0;
    }

    int wordIndex = pixel.y * MASK_WORDS_PER_ROW + pixel.x / MASK_WORD_BITS;
    int bitIndex = pixel.x - (pixel.x / MASK_WORD_BITS) * MASK_WORD_BITS;
    return (kamisama2Mask[wordIndex] & (1 << bitIndex)) != 0 ? 1.0 : 0.0;
}

float sampleMask(vec2 position) {
    ivec2 base = ivec2(floor(position));
    vec2 weight = fract(position);

    float top = mix(maskPixel(base), maskPixel(base + ivec2(1, 0)), weight.x);
    float bottom = mix(
        maskPixel(base + ivec2(0, 1)),
        maskPixel(base + ivec2(1, 1)),
        weight.x
    );
    return mix(top, bottom, weight.y);
}

vec2 inverseRotate(vec2 point, float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return vec2(
        cosine * point.x + sine * point.y,
        -sine * point.x + cosine * point.y
    );
}

float smootherstep(float value) {
    value = clamp(value, 0.0, 1.0);
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}

float ellipseRing(vec2 point, vec2 radius) {
    float distanceFromRing = abs(length(point / radius) - 1.0);
    return 1.0 - smoothstep(0.035, 0.085, distanceFromRing);
}

const float KAMISAMA2_BODY_TOP = 116.0;
const float KAMISAMA2_BODY_BOTTOM = 371.2;
const float KAMISAMA2_BODY_CENTER_X = 128.0;
const vec2 KAMISAMA2_HEAD_PIVOT = vec2(128.0, 116.0);

void standingPose(
    float cycleTime,
    float shortSide,
    out float stretch,
    out float widthScale,
    out float topShift,
    out float firstBend,
    out float secondBend
) {
    float quiet = min(cycleTime, 10.0);
    float micro = iFocus > 0 ? 1.0 : 0.16;
    float quietEnvelope = sin(quiet * 0.3141593);
    quietEnvelope *= quietEnvelope;

    stretch = 1.0 + micro * quietEnvelope * 0.018 * sin(quiet * 0.6283185);
    widthScale = 1.0;
    topShift = micro * quietEnvelope * shortSide * 0.008 *
        sin(quiet * 0.6283185);
    firstBend = micro * quietEnvelope * shortSide * 0.012 *
        sin(quiet * 0.6283185);
    secondBend = micro * quietEnvelope * shortSide * 0.006 *
        sin(quiet * 1.2566371);

    if (cycleTime >= 10.0) {
        float reach = smootherstep((cycleTime - 10.0) / 10.0);
        stretch = mix(1.0, 1.32, reach);
        widthScale = mix(1.0, 0.84, smootherstep(max(0.0, reach - 0.12) / 0.88));
        topShift = 0.0;
        firstBend = shortSide * 0.010 * sin(reach * 3.1415927);
        secondBend = -shortSide * 0.006 * sin(reach * 3.1415927);
    }

    if (cycleTime >= 20.0) {
        float bend = smootherstep((cycleTime - 20.0) / 10.0);
        stretch = mix(1.32, 1.58, bend);
        widthScale = mix(0.84, 0.90, smootherstep(max(0.0, bend - 0.18) / 0.82));
        topShift = iResolution.x * 0.090 * bend;
        firstBend = shortSide * 0.100 * bend;
        secondBend = -shortSide * 0.050 * bend;
    }
}

float standingCenterX(
    float longitudinal,
    vec2 tail,
    float topShift,
    float firstBend,
    float secondBend
) {
    return tail.x + topShift * longitudinal +
        firstBend * sin(3.1415927 * longitudinal) +
        secondBend * sin(6.2831853 * longitudinal);
}

float sampleStandingBody(
    vec2 fragCoord,
    vec2 tail,
    float pixelScale,
    float stretch,
    float widthScale,
    float topShift,
    float firstBend,
    float secondBend
) {
    float sourceSpan = KAMISAMA2_BODY_BOTTOM - KAMISAMA2_BODY_TOP;
    float bodyHeight = sourceSpan * pixelScale * stretch;
    float longitudinal = (tail.y - fragCoord.y) / bodyHeight;
    if (longitudinal < 0.0 || longitudinal > 1.0) return 0.0;

    float centerX = standingCenterX(
        longitudinal,
        tail,
        topShift,
        firstBend,
        secondBend
    );
    float delayedWidth = mix(1.05, widthScale, smootherstep(longitudinal));
    vec2 maskPosition = vec2(
        KAMISAMA2_BODY_CENTER_X +
            (fragCoord.x - centerX) / (pixelScale * delayedWidth),
        KAMISAMA2_BODY_BOTTOM - longitudinal * sourceSpan
    );
    if (maskPosition.x < 78.0 || maskPosition.x > 181.0 ||
        maskPosition.y < KAMISAMA2_BODY_TOP - 3.0 ||
        maskPosition.y > 382.0) return 0.0;

    float neckBlend = smoothstep(
        KAMISAMA2_BODY_TOP - 3.0,
        KAMISAMA2_BODY_TOP + 12.0,
        maskPosition.y
    );
    return sampleMask(maskPosition) * neckBlend;
}

float standingHeadAngle(
    float bodyHeight,
    float topShift,
    float firstBend,
    float secondBend
) {
    float topDerivative = topShift - 3.1415927 * firstBend +
        6.2831853 * secondBend;
    return atan(topDerivative, bodyHeight);
}

float sampleRigidHead(
    vec2 fragCoord,
    vec2 neck,
    float pixelScale,
    float angle,
    out vec2 headMaskPosition
) {
    headMaskPosition = inverseRotate(
        (fragCoord - neck) / pixelScale,
        angle
    ) + KAMISAMA2_HEAD_PIVOT;
    if (headMaskPosition.x < 76.0 || headMaskPosition.x > 184.0 ||
        headMaskPosition.y < 4.0 || headMaskPosition.y > 132.0) return 0.0;

    float neckBlend = 1.0 - smoothstep(116.0, 132.0, headMaskPosition.y);
    return sampleMask(headMaskPosition) * neckBlend;
}

void sampleHeadArtwork(
    vec2 fragCoord,
    vec2 neck,
    float pixelScale,
    float angle,
    out float ink,
    out float halo
) {
    vec2 headMaskPosition;
    ink = sampleRigidHead(
        fragCoord,
        neck,
        pixelScale,
        angle,
        headMaskPosition
    );

    vec2 haloPoint = headMaskPosition - vec2(129.6, 36.8);
    float focusMotion = iFocus > 0 ? 1.0 : 0.14;
    float haloAngle = focusMotion * 0.055 * sin(iTime * 0.3695991 + 0.4);
    haloPoint = inverseRotate(haloPoint, haloAngle);
    float orbit = ellipseRing(haloPoint, vec2(38.4, 12.8));

    float orbitPhase = iFocus > 0 ? iTime * 0.4487989 : 0.5;
    vec2 nodePosition = vec2(
        cos(orbitPhase) * 38.4,
        sin(orbitPhase) * 12.8
    );
    float node = 1.0 - smoothstep(
        1.28,
        2.88,
        length(haloPoint - nodePosition)
    );
    halo = max(orbit * 0.55, node);
}

vec2 superellipsePoint(float angle, vec2 halfExtents) {
    vec2 direction = vec2(cos(angle), sin(angle));
    vec2 normalized = abs(direction) / halfExtents;
    float denominator = pow(
        pow(normalized.x, 6.0) + pow(normalized.y, 6.0),
        1.0 / 6.0
    );
    return direction / max(denominator, 0.0001);
}

vec2 perimeterHalfExtents(float shortSide) {
    return vec2(
        0.5 * iResolution.x / shortSide - 0.12,
        0.5 * iResolution.y / shortSide - 0.21
    );
}

float perimeterCornerAngle(float shortSide) {
    vec2 halfExtents = perimeterHalfExtents(shortSide);
    return atan(halfExtents.y, halfExtents.x);
}

vec2 perimeterScreenPoint(float angle, float shortSide) {
    return 0.5 * iResolution.xy +
        superellipsePoint(angle, perimeterHalfExtents(shortSide)) * shortSide;
}

float perimeterScreenAngle(float angle, float shortSide) {
    float tangentStep = 0.006;
    vec2 halfExtents = perimeterHalfExtents(shortSide);
    vec2 tangent = normalize(
        superellipsePoint(angle + tangentStep, halfExtents) -
        superellipsePoint(angle - tangentStep, halfExtents)
    );
    return atan(tangent.x, -tangent.y);
}

float handDrawnStroke(float distanceToLine, float antialias) {
    return 1.0 - smoothstep(antialias, antialias * 2.8, abs(distanceToLine));
}

float perimeterBody(
    vec2 fragCoord,
    float shortSide,
    float progress,
    vec2 entryNeck,
    float entryAngle,
    out vec2 neck,
    out float headAngle
) {
    vec2 center = 0.5 * iResolution.xy;
    vec2 halfExtents = perimeterHalfExtents(shortSide);

    float cornerAngle = atan(halfExtents.y, halfExtents.x);
    float startAngle = -cornerAngle;
    float headTravel = (6.2831853 + 2.0 * cornerAngle) * smootherstep(progress);
    float headPathAngle = startAngle + headTravel;
    vec2 headBoundary = superellipsePoint(headPathAngle, halfExtents);
    vec2 pathNeck = center + headBoundary * shortSide;
    float settle = smootherstep(progress / 0.08);
    neck = mix(entryNeck, pathNeck, settle);

    float tangentStep = 0.006;
    vec2 tangent = normalize(
        superellipsePoint(headPathAngle + tangentStep, halfExtents) -
        superellipsePoint(headPathAngle - tangentStep, halfExtents)
    );
    float pathAngle = atan(tangent.x, -tangent.y);
    headAngle = mix(entryAngle, pathAngle, settle);

    // The ribbon never leaves this edge band. Keep its superellipse and hatch
    // work away from the terminal's interior, where it cannot contribute.
    vec2 edgeDistance = min(fragCoord, iResolution.xy - fragCoord);
    if (min(edgeDistance.x, edgeDistance.y) > shortSide * 0.28) return 0.0;

    vec2 point = (fragCoord - center) / shortSide;
    float angle = atan(point.y, point.x);
    vec2 boundary = superellipsePoint(angle, halfExtents);
    float radialDistance = length(point) - length(boundary);

    float behind = mod(headPathAngle - angle + 6.2831853, 6.2831853);
    float trailLength = mix(
        2.25,
        4.10,
        0.5 + 0.5 * sin(progress * 9.4247780 + 0.5)
    );
    float trail = 1.0 - smootherstep(
        (behind - (trailLength - 0.16)) / 0.16
    );
    float along = clamp(behind / max(trailLength, 0.001), 0.0, 1.0);
    float halfWidth = mix(0.016, 0.043, smootherstep(along));
    float roughness = 0.0014 * sin(angle * 13.0 + iTime * 0.23) +
        0.0008 * sin(angle * 29.0 - iTime * 0.17);
    float antialias = 1.25 / shortSide;
    float outline = handDrawnStroke(
        abs(radialDistance + roughness) - halfWidth,
        antialias
    );

    float inside = 1.0 - smoothstep(halfWidth * 0.68, halfWidth, abs(radialDistance));
    float hatchPhase = behind * 31.0 + radialDistance * shortSide * 0.24;
    float hatches = (1.0 - smoothstep(0.0, 0.18, abs(sin(hatchPhase)))) *
        inside * mix(0.22, 0.52, along);
    return max(outline, hatches) * trail;
}

float distanceToSegment(vec2 point, vec2 start, vec2 end, out float along) {
    vec2 segment = end - start;
    along = clamp(
        dot(point - start, segment) / max(dot(segment, segment), 0.0001),
        0.0,
        1.0
    );
    return length(point - (start + along * segment));
}

float bridgeBody(
    vec2 fragCoord,
    float shortSide,
    float progress,
    vec2 tail,
    float entryAngle,
    float exitAngle,
    out vec2 neck,
    out float headAngle
) {
    float crossing = sin(3.1415927 * smootherstep(progress));
    neck = mix(tail, vec2(0.12, 0.87) * iResolution.xy, crossing);
    vec2 control = vec2(
        0.5 * (tail.x + neck.x),
        mix(tail.y, 0.58 * iResolution.y, crossing)
    );

    vec2 tangent = normalize(neck - control + vec2(0.001, 0.0));
    float curveAngle = atan(tangent.x, -tangent.y);
    float restingAngle = mix(entryAngle, exitAngle, smootherstep(progress));
    float curveAmount = smootherstep(crossing / 0.15);
    headAngle = mix(restingAngle, curveAngle, curveAmount);

    float margin = shortSide * 0.065;
    vec2 lowerBound = min(min(tail, neck), control) - vec2(margin);
    vec2 upperBound = max(max(tail, neck), control) + vec2(margin);
    if (any(lessThan(fragCoord, lowerBound)) ||
        any(greaterThan(fragCoord, upperBound))) return 0.0;

    float bestDistance = 1.0e20;
    float bestAlong = 0.0;
    vec2 previous = tail;
    for (int index = 1; index <= 12; ++index) {
        float curveTime = float(index) / 12.0;
        vec2 current = mix(
            mix(tail, control, curveTime),
            mix(control, neck, curveTime),
            curveTime
        );
        float segmentAlong;
        float segmentDistance = distanceToSegment(
            fragCoord,
            previous,
            current,
            segmentAlong
        );
        if (segmentDistance < bestDistance) {
            bestDistance = segmentDistance;
            bestAlong = (float(index - 1) + segmentAlong) / 12.0;
        }
        previous = current;
    }

    float halfWidth = shortSide * mix(0.016, 0.045, 1.0 - bestAlong);
    float roughness = shortSide * 0.0012 * sin(bestAlong * 47.0 + iTime * 0.31);
    float antialias = 1.25;
    float outline = handDrawnStroke(
        bestDistance + roughness - halfWidth,
        antialias
    );
    float inside = 1.0 - smoothstep(halfWidth * 0.70, halfWidth, bestDistance);
    float hatches = (1.0 - smoothstep(
        0.0,
        0.20,
        abs(sin(bestAlong * 54.0 + bestDistance * 0.19))
    )) * inside * 0.42;
    return max(outline, hatches) * smoothstep(0.0, 0.08, crossing);
}

float collapseCoil(vec2 fragCoord, float shortSide, float amount) {
    vec2 center = vec2(0.82, 0.89) * iResolution.xy;
    vec2 point = (fragCoord - center) / shortSide;
    float radius = length(point);
    float angle = atan(point.y, point.x);
    float antialias = 1.25 / shortSide;
    float first = handDrawnStroke(
        radius - mix(0.012, 0.055, amount) - 0.003 * sin(angle * 3.0),
        antialias
    );
    float second = handDrawnStroke(
        radius - mix(0.020, 0.082, amount) - 0.002 * sin(angle * 5.0 + 0.7),
        antialias
    );
    return max(first, second * 0.65) * amount;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 terminal = texture(iChannel0, uv);

    float cycleTime = mod(iTime, 78.0);
    float shortSide = min(iResolution.x, iResolution.y);
    vec2 tail = vec2(0.82, 0.97) * iResolution.xy;
    float pixelScale = (0.69 * iResolution.y) / float(MASK_HEIGHT);
    float sourceSpan = KAMISAMA2_BODY_BOTTOM - KAMISAMA2_BODY_TOP;
    float cornerAngle = perimeterCornerAngle(shortSide);
    vec2 perimeterStart = perimeterScreenPoint(-cornerAngle, shortSide);
    vec2 perimeterEnd = perimeterScreenPoint(cornerAngle, shortSide);
    float perimeterEndAngle = perimeterScreenAngle(cornerAngle, shortSide);

    float standingWeight = 0.0;
    if (cycleTime < 32.0) {
        standingWeight = 1.0 - smootherstep((cycleTime - 28.0) / 4.0);
    } else if (cycleTime >= 62.0) {
        standingWeight = smootherstep((cycleTime - 62.0) / 4.0);
    }

    float stretch;
    float widthScale;
    float topShift;
    float firstBend;
    float secondBend;
    standingPose(
        min(cycleTime, 30.0),
        shortSide,
        stretch,
        widthScale,
        topShift,
        firstBend,
        secondBend
    );

    // Land the standing reach on the exact point used to start the perimeter
    // run. This removes the doubled head that a merely visual crossfade causes.
    if (cycleTime >= 20.0 && cycleTime < 62.0) {
        float handoff = smootherstep((min(cycleTime, 30.0) - 20.0) / 10.0);
        float perimeterStretch =
            (tail.y - perimeterStart.y) / (sourceSpan * pixelScale);
        stretch = mix(1.32, perimeterStretch, handoff);
        topShift = mix(0.0, perimeterStart.x - tail.x, handoff);
    }

    float handoffStretch =
        (tail.y - perimeterEnd.y) / (sourceSpan * pixelScale);
    float handoffShift = perimeterEnd.x - tail.x;
    float handoffHeight = sourceSpan * pixelScale * handoffStretch;
    float handoffAngle = standingHeadAngle(
        handoffHeight,
        handoffShift,
        0.0,
        0.0
    );

    float collapseAmount = 0.0;
    if (cycleTime >= 62.0) {
        if (cycleTime < 70.0) {
            float collapse = smootherstep((cycleTime - 66.0) / 4.0);
            stretch = mix(handoffStretch, 0.09, collapse);
            widthScale = mix(1.10, 1.34, collapse);
            topShift = mix(handoffShift, 0.0, collapse) +
                shortSide * 0.012 * sin(collapse * 3.1415927);
            firstBend = shortSide * 0.032 * sin(collapse * 3.1415927);
            secondBend = -shortSide * 0.018 * sin(collapse * 6.2831853);
            collapseAmount = collapse;
        } else {
            float recover = smootherstep((cycleTime - 70.0) / 8.0);
            stretch = mix(0.09, 1.0, recover);
            widthScale = mix(1.34, 1.0, recover);
            topShift = shortSide * 0.018 * sin(recover * 3.1415927) *
                (1.0 - recover);
            firstBend = shortSide * 0.050 * sin(recover * 3.1415927) *
                (1.0 - recover);
            secondBend = -shortSide * 0.024 * sin(recover * 6.2831853) *
                (1.0 - recover);
            collapseAmount = 1.0 - recover;
        }
    }

    float ink = 0.0;
    float halo = 0.0;

    if (standingWeight > 0.001) {
        float bodyInk = sampleStandingBody(
            fragCoord,
            tail,
            pixelScale,
            stretch,
            widthScale,
            topShift,
            firstBend,
            secondBend
        );
        float bodyHeight = sourceSpan * pixelScale * stretch;
        vec2 neck = vec2(
            standingCenterX(1.0, tail, topShift, firstBend, secondBend),
            tail.y - bodyHeight
        );
        float headAngle = standingHeadAngle(
            bodyHeight,
            topShift,
            firstBend,
            secondBend
        );
        float headInk;
        float headHalo;
        sampleHeadArtwork(
            fragCoord,
            neck,
            pixelScale,
            headAngle,
            headInk,
            headHalo
        );
        float coil = collapseCoil(fragCoord, shortSide, collapseAmount);
        ink += standingWeight * max(max(bodyInk, headInk), coil * 0.72);
        halo += standingWeight * headHalo;
    }

    if (cycleTime >= 28.0 && cycleTime < 56.0) {
        float enter = smootherstep((cycleTime - 28.0) / 4.0);
        float leave = 1.0 - smootherstep((cycleTime - 52.0) / 4.0);
        float perimeterWeight = enter * leave;
        float perimeterProgress = clamp((cycleTime - 30.0) / 24.0, 0.0, 1.0);
        vec2 perimeterNeck;
        float perimeterAngle;
        float perimeterInk = perimeterBody(
            fragCoord,
            shortSide,
            perimeterProgress,
            vec2(
                standingCenterX(
                    1.0,
                    tail,
                    topShift,
                    firstBend,
                    secondBend
                ),
                tail.y - sourceSpan * pixelScale * stretch
            ),
            standingHeadAngle(
                sourceSpan * pixelScale * stretch,
                topShift,
                firstBend,
                secondBend
            ),
            perimeterNeck,
            perimeterAngle
        );
        float perimeterHeadInk;
        float perimeterHalo;
        sampleHeadArtwork(
            fragCoord,
            perimeterNeck,
            pixelScale,
            perimeterAngle,
            perimeterHeadInk,
            perimeterHalo
        );
        ink += perimeterWeight * max(perimeterInk, perimeterHeadInk);
        halo += perimeterWeight * perimeterHalo;
    }

    if (cycleTime >= 52.0 && cycleTime < 66.0) {
        float enter = smootherstep((cycleTime - 52.0) / 4.0);
        float leave = 1.0 - smootherstep((cycleTime - 62.0) / 4.0);
        float bridgeWeight = enter * leave;
        float bridgeProgress = clamp((cycleTime - 54.0) / 8.0, 0.0, 1.0);
        vec2 bridgeNeck;
        float bridgeAngle;
        float bridgeInk = bridgeBody(
            fragCoord,
            shortSide,
            bridgeProgress,
            perimeterEnd,
            perimeterEndAngle,
            handoffAngle,
            bridgeNeck,
            bridgeAngle
        );
        float bridgeHeadInk;
        float bridgeHalo;
        sampleHeadArtwork(
            fragCoord,
            bridgeNeck,
            pixelScale,
            bridgeAngle,
            bridgeHeadInk,
            bridgeHalo
        );
        ink += bridgeWeight * max(bridgeInk, bridgeHeadInk);
        halo += bridgeWeight * bridgeHalo;
    }

    // Detect terminal foreground pixels and let glyphs dominate the overlay.
    float foregroundDistance = length(terminal.rgb - iBackgroundColor);
    float bareBackground = 1.0 - smoothstep(0.055, 0.20, foregroundDistance);
    float readability = mix(0.08, 1.0, bareBackground);

    vec3 lineColor = mix(iPalette[8], iForegroundColor, 0.22);
    float overlay = clamp(ink * 0.076 + halo * 0.028, 0.0, 0.10);
    overlay *= readability;

    fragColor = vec4(mix(terminal.rgb, lineColor, overlay), terminal.a);
}
