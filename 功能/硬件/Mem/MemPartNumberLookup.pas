unit MemPartNumberLookup;

{
  内存型号 / 品牌前缀 → 中文厂商名。
  由 tools/gen_mem_mfg_prefix.py 自动生成，请勿手工编辑查表函数。
}

interface

function MemPartNumberManufacturerText(const AText: string): string;

implementation

uses
  SysUtils;

function MemPartNumberManufacturerText(const AText: string): string;
var
  s: string;
begin
  Result := '';
  s := UpperCase(Trim(AText));
  if s = '' then
    Exit;

  if (Copy(s, 1, 3) = 'VAM') or (Copy(s, 1, 3) = 'VMA') then
    Exit('阿斯加特');
  if (Copy(s, 1, 3) = 'TRA') then
    Exit('威旭');
  if (Pos('V-COLOR', s) > 0) or (Pos('VCOLOR', s) > 0) then
    Exit('威旭');
  if (Copy(s, 1, 3) = 'SED') or (Copy(s, 1, 3) = 'JHR') then
    Exit('玖合');
  if (Copy(s, 1, 4) = 'GMGX') or (Copy(s, 1, 4) = 'GLOW') then
    Exit('光威');
  if (Pos('GLOWAY', s) > 0) then
    Exit('光威');
  if (Copy(s, 1, 4) = 'MKLD') or (Copy(s, 1, 3) = 'KBK') then
    Exit('金百达');
  if (Pos('KINGBANK', s) > 0) then
    Exit('金百达');
  if (Copy(s, 1, 3) = 'KVR') or (Copy(s, 1, 3) = 'KCP') then
    Exit('金士顿');
  if (Pos('KINGSTON', s) > 0) then
    Exit('金士顿');
  if (Copy(s, 1, 2) = 'KF') then
    Exit('金士顿');
  if (Copy(s, 1, 3) = 'CMK') or (Copy(s, 1, 3) = 'CMW') or (Copy(s, 1, 3) = 'CMS') then
    Exit('海盗船');
  if (Pos('CORSAIR', s) > 0) then
    Exit('海盗船');
  if (Copy(s, 1, 2) = 'F4') then
    Exit('芝奇');
  if (Pos('G.SKILL', s) > 0) or (Pos('GSKILL', s) > 0) or (Pos('G SKILL', s) > 0) then
    Exit('芝奇');
  if (Copy(s, 1, 3) = 'HMA') or (Copy(s, 1, 3) = 'HMC') then
    Exit('海力士');
  if (Pos('HYNIX', s) > 0) or (Pos('SKHYNIX', s) > 0) or (Pos('SK HYNIX', s) > 0) then
    Exit('海力士');
  if (Copy(s, 1, 2) = 'HX') or (Copy(s, 1, 2) = 'H5') then
    Exit('海力士');
  if (Copy(s, 1, 3) = 'M37') or (Copy(s, 1, 3) = 'MTA') then
    Exit('美光');
  if (Pos('MICRON', s) > 0) then
    Exit('美光');
  if (Copy(s, 1, 3) = 'M38') then
    Exit('英睿达');
  if (Pos('CRUCIAL', s) > 0) then
    Exit('英睿达');
  if (Copy(s, 1, 2) = 'BL') or (Copy(s, 1, 2) = 'CT') then
    Exit('英睿达');
  if (Copy(s, 1, 3) = 'AD4') or (Copy(s, 1, 3) = 'AD5') then
    Exit('威刚');
  if (Pos('A-DATA', s) > 0) or (Pos('ADATA', s) > 0) then
    Exit('威刚');
  if (Copy(s, 1, 3) = 'PVS') or (Copy(s, 1, 3) = 'PSD') then
    Exit('博帝');
  if (Pos('PATRIOT', s) > 0) then
    Exit('博帝');
  if (Copy(s, 1, 3) = 'KLE') then
    Exit('科赋');
  if (Pos('KLEVV', s) > 0) then
    Exit('科赋');
  if (Copy(s, 1, 3) = 'GAL') then
    Exit('影驰');
  if (Pos('GALAX', s) > 0) then
    Exit('影驰');
  if (Copy(s, 1, 2) = 'TE') then
    Exit('十铨');
  if (Pos('TEAMGROUP', s) > 0) or (Pos('TEAM GROUP', s) > 0) then
    Exit('十铨');
  if (Copy(s, 1, 3) = 'AP4') or (Copy(s, 1, 3) = 'APA') then
    Exit('宇瞻');
  if (Pos('APACER', s) > 0) then
    Exit('宇瞻');
  if (Copy(s, 1, 3) = 'NTI') then
    Exit('朗科');
  if (Pos('NETAC', s) > 0) then
    Exit('朗科');
  if (Copy(s, 1, 3) = 'BWU') then
    Exit('佰维');
  if (Pos('BIWIN', s) > 0) then
    Exit('佰维');
  if (Copy(s, 1, 3) = 'M4U') then
    Exit('宜鼎');
  if (Pos('INNODISK', s) > 0) then
    Exit('宜鼎');
  if (Copy(s, 1, 3) = 'RMX') then
    Exit('记忆科技');
  if (Pos('RAMAXEL', s) > 0) then
    Exit('记忆科技');
  if (Copy(s, 1, 3) = 'TMS') then
    Exit('泰酷');
  if (Pos('TIMETEC', s) > 0) then
    Exit('泰酷');
  if (Pos('SAMSUNG', s) > 0) then
    Exit('三星');
  if (Copy(s, 1, 3) = 'MAX') then
    Exit('铭瑄');
  if (Pos('MAXSUN', s) > 0) then
    Exit('铭瑄');
  if (Copy(s, 1, 3) = 'OLO') then
    Exit('欧乐');
  if (Pos('OLOY', s) > 0) then
    Exit('欧乐');
  if (Copy(s, 1, 3) = 'PNY') then
    Exit('必恩威');
  if (Pos('TRANSCEND', s) > 0) then
    Exit('创见');
  if (Pos('LEXAR', s) > 0) then
    Exit('雷克沙');
  if (Pos('SILICON POWER', s) > 0) then
    Exit('广颖');
  if (Pos('GEIL', s) > 0) then
    Exit('金邦');
  if (Pos('OCZ', s) > 0) then
    Exit('奥睿科');
  if (Pos('NANYA', s) > 0) then
    Exit('南亚');
  if (Pos('MUSHKIN', s) > 0) then
    Exit('摩仕金');
  if (Pos('COLORFUL', s) > 0) then
    Exit('七彩虹');
  if (Pos('LENOVO', s) > 0) then
    Exit('联想');
  if (Pos('DELL', s) > 0) then
    Exit('戴尔');
  if (Pos('ASUS', s) > 0) then
    Exit('华硕');
  if (Pos('GIGABYTE', s) > 0) then
    Exit('技嘉');
  if (Pos('ASROCK', s) > 0) then
    Exit('华擎');
  if (Pos('ZOTAC', s) > 0) then
    Exit('索泰');
  if (Pos('EVGA', s) > 0) then
    Exit('艾维克');
  if (Pos('MSI', s) > 0) then
    Exit('微星');
  if (Pos('ACER', s) > 0) then
    Exit('宏碁');
  if (Pos('LONGSYS', s) > 0) or (Pos('FORESEE', s) > 0) then
    Exit('江波龙');
  if (Pos('YMTC', s) > 0) then
    Exit('长江存储');
  if (Pos('CXMT', s) > 0) then
    Exit('长鑫存储');
  if (Pos('KINGSPEC', s) > 0) then
    Exit('金胜维');
  if (Pos('NEO FORZA', s) > 0) then
    Exit('恩佛莎');
  if (Pos('SUPER TALENT', s) > 0) then
    Exit('超频王');
  if (Pos('KINGMAX', s) > 0) then
    Exit('胜创');
  if (Pos('INFINEON', s) > 0) then
    Exit('英飞凌');
  if (Pos('WINBOND', s) > 0) then
    Exit('华邦');
  if (Pos('ELPIDA', s) > 0) then
    Exit('尔必达');
  if (Pos('INTEL', s) > 0) then
    Exit('英特尔');
  if (Pos('ASGARD', s) > 0) then
    Exit('阿斯加特');
end;

end.
