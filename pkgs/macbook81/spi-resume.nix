# S3 唤醒后恢复 MacBook8,1 的 SPI 控制器寄存器，并重新绑定 pxa2xx_spi_pci。
# deep S3 会清掉 GSPI 控制器（0000:00:15.4）的时钟/复位/CS 寄存器，Apple 固件不恢复它们，
# 不修的话 applespi 每次传输都超时（-110），唤醒后内置键盘与触控板失效。
# 逻辑取自 projectmushroom/macbook81-linux-fixes 的 95-macbook-spi-resume（MIT）。
{
  writeShellScriptBin,
  python3,
}:
writeShellScriptBin "macbook81-spi-resume" ''
  set -u

  DEV=0000:00:15.4
  DRV=/sys/bus/pci/drivers/pxa2xx_spi_pci
  SYSDEV=/sys/bus/pci/devices/$DEV

  [ -e "$SYSDEV" ] || exit 0

  # 先解绑，释放 MMIO 区域，/dev/mem 才能映射（IO_STRICT_DEVMEM 打开时也成立）。
  if [ -e "$SYSDEV/driver" ]; then
    echo "$DEV" > "$DRV/unbind" || exit 1
  fi

  ${python3}/bin/python3 - "$SYSDEV" <<'PY'
  import mmap, struct, sys

  sysdev = sys.argv[1]
  with open(f"{sysdev}/resource") as f:
      bar = int(f.readline().split()[0], 16)

  fd = open("/dev/mem", "r+b")
  m = mmap.mmap(fd.fileno(), 0x1000, mmap.MAP_SHARED,
                mmap.PROT_READ | mmap.PROT_WRITE, offset=bar)

  def w32(off, val):
      m[off:off + 4] = struct.pack("<I", val)

  w32(0x804, 0x3)  # 解除 function reset
  w32(0x800, 0x1)  # 开时钟
  w32(0x818, 0x3)  # CS 控制：软件模式 | CS 拉高
  m.close()
  PY

  rc=$?
  echo "$DEV" > "$DRV/bind"
  exit $rc
''
