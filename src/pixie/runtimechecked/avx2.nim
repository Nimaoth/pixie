import chroma, nimsimd/avx2

when defined(gcc) or defined(clang):
  {.localPassc: "-mavx2".}

when defined(release):
  {.push checks: off.}

proc isOneColorAvx2*(data: ptr UncheckedArray[ColorRGBX], len: int): bool =
  result = true

  let color = data[0]

  var i: int
  while i < len and (cast[uint](data[i].addr) and 31) != 0: # Align to 32 bytes
    if data[i] != color:
      return false
    inc i

  let
    colorVec = mm256_set1_epi32(cast[int32](color))
    iterations = (len - i) div 16
  for _ in 0 ..< iterations:
    let
      values0 = mm256_load_si256(data[i].addr)
      values1 = mm256_load_si256(data[i + 8].addr)
      eq0 = mm256_cmpeq_epi8(values0, colorVec)
      eq1 = mm256_cmpeq_epi8(values1, colorVec)
      eq01 = mm256_and_si256(eq0, eq1)
    if mm256_movemask_epi8(eq01) != cast[int32](0xffffffff):
      return false
    i += 16

  for i in i ..< len:
    if data[i] != color:
      return false

proc isTransparentAvx2*(data: ptr UncheckedArray[ColorRGBX], len: int): bool =
  result = true

  var i: int
  while i < len and (cast[uint](data[i].addr) and 31) != 0: # Align to 32 bytes
    if data[i].a != 0:
      return false
    inc i

  let
    vecZero = mm256_setzero_si256()
    iterations = (len - i) div 16
  for _ in 0 ..< iterations:
    let
      values0 = mm256_load_si256(data[i].addr)
      values1 = mm256_load_si256(data[i + 8].addr)
      values01 = mm256_or_si256(values0, values1)
      eq = mm256_cmpeq_epi8(values01, vecZero)
    if mm256_movemask_epi8(eq) != cast[int32](0xffffffff):
      return false
    i += 16

  for i in i ..< len:
    if data[i].a != 0:
      return false

proc isOpaqueAvx2*(data: ptr UncheckedArray[ColorRGBX], len: int): bool =
  result = true

  var i: int
  while i < len and (cast[uint](data[i].addr) and 31) != 0: # Align to 32 bytes
    if data[i].a != 255:
      return false
    inc i

  let
    vec255 = mm256_set1_epi8(255)
    iterations = (len - i) div 16
  for _ in 0 ..< iterations:
    let
      values0 = mm256_load_si256(data[i].addr)
      values1 = mm256_load_si256(data[i + 8].addr)
      values01 = mm256_and_si256(values0, values1)
      eq = mm256_cmpeq_epi8(values01, vec255)
    if (mm256_movemask_epi8(eq) and 0x88888888) != 0x88888888:
      return false
    i += 16

  for i in i ..< len:
    if data[i].a != 255:
      return false

proc toPremultipliedAlphaAvx2*(
  data: ptr UncheckedArray[uint32],
  len: int
): int =
  let
    alphaMask = mm256_set1_epi32(cast[int32](0xff000000))
    oddMask = mm256_set1_epi16(cast[int16](0xff00))
    div255 = mm256_set1_epi16(cast[int16](0x8081))
  for _ in 0 ..< len div 8:
    let
      values = mm256_loadu_si256(data[result].addr)
      alpha = mm256_and_si256(values, alphaMask)
      eq = mm256_cmpeq_epi8(values, alphaMask)
    if (mm256_movemask_epi8(eq) and 0x88888888) != 0x88888888:
      let
        evenMultiplier = mm256_or_si256(alpha, mm256_srli_epi32(alpha, 16))
        oddMultiplier = mm256_or_si256(evenMultiplier, alphaMask)
      var
        colorsEven = mm256_slli_epi16(values, 8)
        colorsOdd = mm256_and_si256(values, oddMask)
      colorsEven = mm256_mulhi_epu16(colorsEven, evenMultiplier)
      colorsOdd = mm256_mulhi_epu16(colorsOdd, oddMultiplier)
      colorsEven = mm256_srli_epi16(mm256_mulhi_epu16(colorsEven, div255), 7)
      colorsOdd = mm256_srli_epi16(mm256_mulhi_epu16(colorsOdd, div255), 7)
      mm256_storeu_si256(
        data[result].addr,
        mm256_or_si256(colorsEven, mm256_slli_epi16(colorsOdd, 8))
      )
    result += 8

when defined(release):
  {.pop.}
