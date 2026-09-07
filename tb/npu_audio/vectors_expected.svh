// OTOMATIK URETILDI - gen_vectors.py  (tohum=20260831)
// Elle duzenlemeyin. Yeniden uretmek icin:
//     python tb/npu_audio/gen_vectors.py
localparam int VEKTOR_SAYISI = 7;
localparam int VEKTOR_WORD   = 490;

localparam logic [1:0] BEKLENEN_SINIF [0:6] = '{2'd3, 2'd0, 2'd1, 2'd2, 2'd3, 2'd2, 2'd3};
localparam int BEKLENEN_LOGIT0 [0:6] = '{-128, 25, -128, -22, -128, 6, -1};
localparam int BEKLENEN_LOGIT1 [0:6] = '{79, 21, 120, 23, 119, 8, 19};
localparam int BEKLENEN_LOGIT2 [0:6] = '{83, 17, 77, 25, 126, 35, 6};
localparam int BEKLENEN_LOGIT3 [0:6] = '{109, -3, 102, 25, 127, 5, 26};
localparam int BEKLENEN_PROB0 [0:6] = '{0, 1820, 0, 19, 0, 234, 194};
localparam int BEKLENEN_PROB1 [0:6] = '{225, 1261, 3381, 1197, 821, 282, 1217};
localparam int BEKLENEN_PROB2 [0:6] = '{326, 873, 65, 1439, 1562, 3364, 369};
localparam int BEKLENEN_PROB3 [0:6] = '{3543, 139, 648, 1439, 1712, 214, 2314};

// Vektor adlari (raporlama icin)
// [0] deterministik_golden
// [1] rastgele_sinif0_silence
// [2] rastgele_sinif1_unknown
// [3] rastgele_sinif2_yes
// [4] rastgele_sinif3_no
// [5] ses_yes
// [6] ses_no
