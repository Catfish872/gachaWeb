"""Original portrait artwork. Standard SVG only, suitable for Godot's SVG importer."""
from pathlib import Path
import math, random, json, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'portraits'
OUT.mkdir(parents=True,exist_ok=True)
CAT=json.loads((ROOT/'data'/'catalog.json').read_text())
class Art:
 def __init__(self, accent, shade, skin='#dec4a6', hair='#e7e3cf', seed=1):
  self.a=accent; self.s=shade; self.skin=skin; self.hair=hair; self.parts=[]
  self.add(f'''<svg xmlns="http://www.w3.org/2000/svg" width="400" height="500" viewBox="0 0 400 500"><defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#101e32"/><stop offset="1" stop-color="#040a16"/></linearGradient>
  <radialGradient id="halo"><stop stop-color="{accent}" stop-opacity=".3"/><stop offset="1" stop-color="{shade}" stop-opacity=".06"/></radialGradient>
  <linearGradient id="cloth" x1="0" x2="1" y2="1"><stop stop-color="{accent}"/><stop offset=".38" stop-color="{shade}"/><stop offset="1" stop-color="#08111e"/></linearGradient>
  <linearGradient id="steel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#c5d8e0"/><stop offset=".22" stop-color="#536f86"/><stop offset=".5" stop-color="#23384e"/><stop offset=".7" stop-color="#7491a0"/><stop offset="1" stop-color="#132334"/></linearGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#f8e2a9"/><stop offset=".46" stop-color="#b28d51"/><stop offset="1" stop-color="#44382e"/></linearGradient>
  <linearGradient id="skin" x1="0" y1="0" x2="1" y2=".6"><stop stop-color="{skin}"/><stop offset="1" stop-color="#7e6962"/></linearGradient>
  <linearGradient id="hair" x1="0" x2="1" y2="1"><stop stop-color="{hair}"/><stop offset="1" stop-color="#283346"/></linearGradient>
  <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#050d1a" stop-opacity="0"/><stop offset="1" stop-color="#050d1a"/></linearGradient>
  </defs>''')
  self.add('<rect width="400" height="500" fill="url(#bg)"/>')
  self.ellipse(200,222,178,213,'url(#halo)',None)
  # A pointed lancet window and radial stained-glass tracery.
  self.path('M38 466 V192 Q40 80 200 28 Q360 80 362 192 V466 Z','#0a1425',accent,.8,opacity='.5')
  self.path('M49 466 V194 Q50 91 200 42 Q350 91 351 194 V466', 'none','#52636c',1)
  self.ellipse(200,192,137,137,'url(#halo)',accent,1,opacity='.55')
  self.ellipse(200,192,124,124,'none','#b59b6f',1,opacity='.5')
  self.ellipse(200,192,111,111,'none',accent,.6,opacity='.25')
  for k in range(16):
   th=math.pi*2*k/16
   xx=lambda r:200+math.sin(th)*r
   yy=lambda r:192+math.cos(th)*r
   self.line(xx(139),yy(139),xx(148),yy(148),'#b9a775',1)
   self.path(f'M{xx(146)} {yy(146)} L{xx(151)+math.cos(th)*3} {yy(151)-math.sin(th)*3} L{xx(157)} {yy(157)} L{xx(151)-math.cos(th)*3} {yy(151)+math.sin(th)*3} Z',accent,None)
   if k%2==0:self.line(xx(111),yy(111),xx(125),yy(125),accent,1)
  for x in [27,373]:
   self.path(f'M{x} 54 V443 M{x-5} 96 H{x+5} M{x-5} 405 H{x+5}','none','#826b47',1)
   for y in [73,424]:self.path(f'M{x} {y-6} l4 6 -4 6 -4 -6 Z','#c0a16a',None)
  r=random.Random(seed)
  for _ in range(35):
   x,y=r.uniform(52,348),r.uniform(45,464)
   self.ellipse(x,y,r.uniform(.4,1.2),r.uniform(.4,1.2),accent,None,opacity=str(r.uniform(.1,.5)))
  self.ellipse(200,452,128,18,'#020711',None)
 def add(self,s):self.parts.append(s)
 def path(self,d,fill='url(#steel)',stroke='#07101c',sw=2,**kwargs):
  attrs=' '.join(f'{k.replace("_","-")}="{v}"' for k,v in kwargs.items())
  self.add(f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"' if stroke else '')+f' {attrs}/>')
 def line(self,x,y,xx,yy,c='#8da6b7',sw=1,**kw):self.path(f'M{x} {y} L{xx} {yy}','none',c,sw,**kw)
 def ellipse(self,x,y,rx,ry,f,s=None,sw=1,**kw):
  attrs=' '.join(f'{k.replace("_","-")}="{v}"' for k,v in kw.items())
  self.add(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{f}"'+(f' stroke="{s}" stroke-width="{sw}"' if s else '')+f' {attrs}/>')
 def jewel(self,x,y,r=10,c=None):
  self.path(f'M{x} {y-r} L{x+r*.62} {y} L{x} {y+r} L{x-r*.62} {y} Z',c or self.a,'#c7b37a',1)
  self.line(x,y-r+3,x-r*.35,y,'#e7f4e6',1)
 def group(self,transform):self.add(f'<g transform="{transform}">')
 def end(self):self.add('</g>')
 def face(self,x=200,y=154,shape='human',long_hair=False):
  if long_hair:self.path(f'M{x-34} {y-27} Q{x-48} {y+9} {x-43} {y+101} L{x-20} {y+82} {x+26} {y+99} {x+44} {y+94} Q{x+37} {y+25} {x+38} {y-16} Z','url(#hair)')
  self.path(f'M{x-11} {y+23} L{x-13} {y+48} {x} {y+57} {x+16} {y+43} {x+11} {y+23} Z','url(#skin)')
  self.path(f'M{x-28} {y-14} L{x-26} {y+15} Q{x-19} {y+33} {x} {y+39} Q{x+22} {y+30} {x+27} {y+12} L{x+28} {y-17} Q{x} {y-42} {x-28} {y-14} Z','url(#skin)')
  if shape=='elf':
   self.path(f'M{x-28} {y} L{x-51} {y-11} {x-35} {y+17} {x-25} {y+11} M{x+28} {y} L{x+51} {y-11} {x+35} {y+17} {x+25} {y+11}','url(#skin)')
  self.path(f'M{x-20} {y+2} l12 -2 M{x+7} {y} l12 2','none','#302f37',2.5)
  self.path(f'M{x-18} {y+5} l9 1 M{x+10} {y+6} l7 -1','none',self.a,1.7)
  self.path(f'M{x+2} {y+5} l-3 11 5 1 M{x-6} {y+26} q7 3 14 -1','none','#725c59',1.3)
 def haircap(self,x=200,y=154,long=False):
  self.path(f'M{x-30} {y+2} L{x-35} {y-21} {x-22} {y-43} {x-4} {y-49} {x+22} {y-38} {x+35} {y-19} {x+29} {y+9} {x+19} {y-14} {x+6} {y-23} {x-6} {y-7} {x-12} {y-17} {x-24} {y-6} Z','url(#hair)')
  self.path(f'M{x-25} {y-22} Q{x-8} {y-43} {x+15} {y-30} M{x+1} {y-38} L{x-10} {y-13}','none',self.hair,1.2,opacity='.55')
 def finish(self,name):
  self.add('<rect y="455" width="400" height="45" fill="url(#fade)"/>')
  self.path('M72 476 H164 L178 470 L200 477 L222 470 L236 476 H328','none','#b99b60',1,opacity='.65')
  self.jewel(200,477,5,'#c7a76a')
  self.add('</svg>')
  p=OUT/f'{name}.svg';p.write_text('\n'.join(self.parts));ET.parse(p)

def cape(a,d=None):a.path(d or 'M157 192 Q91 211 81 274 L48 435 Q100 471 166 447 L224 449 Q283 473 347 436 L313 257 Q289 208 241 193 Z','url(#cloth)','#07101c',2.5)
def boots(a):
 a.path('M157 351 L153 411 L134 447 Q156 457 183 445 L192 369 Z')
 a.path('M209 367 L222 444 Q251 454 270 444 L245 414 L241 351 Z')
 a.path('M155 403 L180 409 M224 405 L248 401','none','#af9b70',2)
def breastplate(a):
 a.path('M157 201 L185 187 L215 187 L247 202 L238 273 L219 297 L178 297 L156 271 Z')
 a.path('M159 210 L197 224 L241 207 L232 249 L202 275 L166 250 Z','#21394c','#8ca3ae',1)
 a.path('M164 213 L194 229 L190 257 L170 244 Z','#557082',None)
 a.path('M203 226 L235 215 L227 242 L203 261 Z','#132b3a',None)
 a.path('M176 281 L221 281 L235 297 L199 307 L166 296 Z','url(#gold)')
 a.jewel(200,235,13)
def pauldrons(a):
 a.path('M153 196 L122 203 L111 235 L152 250 L173 225 Z')
 a.path('M242 195 L277 204 L291 236 L250 250 L228 224 Z')
 a.path('M119 226 L151 237 L164 217 M237 217 L253 239 L281 226','none','#b9a36d',2)
def sword(a,x=298,y=162,angle=0,length=246):
 a.group(f'translate({x} {y}) rotate({angle})')
 a.path(f'M0 -90 L11 -67 L8 {length-120} L0 {length-111} L-8 {length-120} L-11 -67 Z','url(#steel)','#a3c3ca',1)
 a.path(f'M0 -83 V{length-118}','none','#e8eef0',1.5)
 a.path(f'M-27 {length-116} Q0 {length-131} 27 {length-116} L24 {length-106} Q0 {length-115} -24 {length-106} Z','url(#gold)')
 a.path(f'M-5 {length-108} V{length-77} L0 {length-69} L5 {length-77} V{length-108} Z','#283b4e','#bea46e',1.5)
 a.jewel(0,length-75,6);a.end()
def staff(a,x=108,y=114):
 a.path(f'M{x} {y+28} L{x+7} 443 L{x+14} 443 L{x+9} {y+28} Z','url(#gold)')
 a.path(f'M{x+4} {y+34} C{x-31} {y+20} {x-24} {y-17} {x+4} {y-35} C{x+31} {y-13} {x+34} {y+17} {x+4} {y+34} Z','url(#cloth)','#cab780',2)
 a.jewel(x+4,y,21)

# GUS: fully armored thunder lancer, wind-blown plumage and lightning blade.
a=Art('#f3ce65','#695024',hair='#ede2ad',seed=3)
a.path('M180 135 Q132 90 151 63 Q186 64 201 104 Q213 81 246 77 L224 126 Z','url(#cloth)')
cape(a);boots(a)
a.path('M164 288 L196 302 L181 378 L145 385 Z M204 302 L235 288 L254 380 L218 377 Z','url(#cloth)','#ba9a63',1)
sword(a,303,137,-9,269)
a.path('M124 238 L111 283 L134 318 L151 305 L137 276 L158 249 Z')
a.path('M274 237 L293 269 L309 280 L301 301 L277 288 L250 249 Z')
breastplate(a);pauldrons(a);a.face();a.haircap()
a.path('M171 135 L182 116 L201 123 L221 117 L234 137 L222 145 L201 134 L178 145 Z','url(#gold)')
a.path('M152 205 L147 183 L163 195 L172 216 Z M245 205 L255 182 L257 199 L274 204 L254 216 Z','url(#gold)')
a.path('M80 193 L102 158 L95 190 L113 186 L92 224 L99 197 Z M308 77 L285 109 L301 107 L289 131 L324 95 L307 97 Z',a.a,None,opacity='.9')
a.finish('gus')

# SHANA: elven forest healer, antler-crown, healing staff and foliage.
a=Art('#8be0b0','#275a46',skin='#e3cdb1',hair='#b8d2bd',seed=4)
a.path('M168 176 Q128 206 106 310 L75 421 L133 438 L172 318 L217 413 L300 436 Q274 318 251 210 Z','url(#cloth)')
a.face(long_hair=True,shape='elf')
a.path('M164 200 L185 194 L201 217 L218 194 L238 202 L250 279 L235 315 L289 450 Q204 473 121 445 L164 311 L150 270 Z','url(#cloth)','#a4c6a3',1.5)
a.path('M197 234 L179 306 L153 441 L194 454 L217 309 Z','#315249','#b4b28a',1)
a.path('M215 308 L247 438 L224 445 L200 361 Z','#122b2c',None)
a.path('M160 207 L138 213 L119 264 L100 283 L111 299 L143 283 L166 238 Z','url(#cloth)')
a.path('M236 209 L253 217 L279 271 L295 266 L301 283 L273 298 L244 267 L226 237 Z','url(#cloth)')
a.path('M99 280 L110 277 L122 289 L114 303 L105 303 Z M285 264 L296 253 L310 256 L317 268 L305 281 L292 278 Z','url(#skin)')
staff(a,103,161)
a.haircap()
a.path('M171 128 L156 112 L152 86 M159 114 L140 104 L137 89 M224 129 L241 110 L244 84 M240 111 L257 103 L263 87','none','#c1b98a',3)
a.path('M172 135 Q201 113 229 134 L220 145 L201 139 L180 145 Z','url(#gold)')
a.jewel(201,135,11);a.jewel(201,263,14)
for x,y,s in [(82,340,1),(301,217,-1),(315,357,-1),(114,139,1),(154,90,1),(259,92,-1)]:
 a.group(f'translate({x} {y}) scale({s} 1)');a.path('M0 0 Q-15 -27 -30 -23 Q-30 -3 0 0 Z','#60ab7d','#aacda0',.6);a.line(-25,-19,0,0,'#c6dfad',.6);a.end()
a.ellipse(304,248,21,21,'url(#halo)',a.a,1);a.jewel(304,247,11)
a.finish('shana')

# LORIN: stalwart full-plate shield bearer.
a=Art('#77bff2','#22496c',skin='#c6a582',hair='#b8bec4',seed=5)
cape(a);boots(a);a.path('M153 294 L185 303 L187 365 L153 385 L135 367 Z M204 305 L241 294 L267 365 L232 383 L210 363 Z')
sword(a,298,157,8,270)
a.path('M252 225 L279 254 L287 283 L309 296 L297 319 L269 302 L248 265 Z')
breastplate(a);pauldrons(a);a.face();a.haircap()
a.path('M174 177 L184 187 L201 195 L219 186 L229 173 L222 197 L202 209 L179 197 Z','#8b969b')
a.path('M178 157 L181 176 L201 191 L221 176 L225 155 L216 169 L202 174 L188 168 Z','url(#hair)')
a.path('M70 246 Q111 224 162 240 L173 335 Q150 384 113 407 Q72 374 57 331 Z','url(#steel)','#c4b180',3)
a.path('M77 253 Q118 236 152 250 L160 329 Q144 366 113 392 Q82 364 69 330 Z','url(#cloth)','#91afbd',1.5)
a.path('M112 254 L121 296 L150 310 L122 323 L113 373 L104 323 L78 311 L104 296 Z','url(#gold)')
a.jewel(114,311,19)
a.finish('lorin')

# EMBER: agile volcanic hunter, crimson scarf and paired curved daggers.
a=Art('#ff8b63','#713931',skin='#c99b76',hair='#413541',seed=6)
a.path('M182 191 Q132 156 89 186 Q42 212 73 252 Q66 202 115 211 L166 230 Z','url(#cloth)')
a.path('M224 191 Q265 161 315 184 L345 221 L314 214 L333 241 L280 221 L230 219 Z','url(#cloth)')
a.path('M164 293 L190 307 L175 374 L160 432 L132 443 L140 410 L145 360 Z M205 310 L231 295 L250 352 L245 416 L265 439 L238 447 L222 417 L217 366 Z','#242c37','#b68c63',1)
a.path('M151 202 L181 191 L200 217 L221 188 L249 204 L236 280 L217 311 L176 307 L150 270 Z','#233342','#95785d',1.5)
a.path('M170 205 L180 260 L202 283 L224 259 L232 204 L212 222 L199 239 L185 220 Z','url(#cloth)')
a.path('M149 210 L126 233 L108 292 L83 310 L97 328 L131 311 L155 265 L169 230 Z','#303b48','#b88b62',1)
a.path('M246 213 L266 234 L285 280 L312 285 L315 304 L271 306 L242 264 L230 234 Z','#303b48','#b88b62',1)
a.path('M85 305 L96 309 L105 321 L92 332 L81 320 Z M304 283 L320 285 L326 296 L318 307 L307 302 Z','url(#skin)')
for x,y,ang in [(83,324,40),(321,298,-42)]:
 a.group(f'translate({x} {y}) rotate({ang})');a.path('M-4 8 L-5 -12 Q-32 -78 0 -112 Q-5 -67 12 -19 L5 8 Z','url(#steel)','#dcc5a4',1.5);a.path('M-15 -11 H18 L15 -4 H-12 Z','url(#gold)');a.end()
a.face();a.haircap()
a.path('M174 169 Q199 176 226 164 L228 190 L205 206 L176 193 Z','url(#cloth)','#cc8661',1)
a.path('M172 280 L227 279 L235 292 L173 300 Z','url(#gold)');a.jewel(203,290,9)
a.path('M175 134 L171 108 L184 119 L201 102 L212 117 L225 110 L230 137 L214 127 L204 137 L190 124 Z','#413442','#b16c57',1)
a.finish('ember')

# ZEPH: swift wandering ranger, feathered hat, sword and streaming cloak.
a=Art('#8ed6bf','#24524f',skin='#dbb99c',hair='#879e95',seed=7)
a.path('M168 194 Q119 220 101 304 Q70 358 63 397 L109 382 L95 420 L163 400 L195 307 L250 239 Z','url(#cloth)','#749c86',1)
a.path('M172 292 L198 302 L180 361 L168 425 L143 445 L128 438 L144 411 L147 351 Z M203 307 L231 297 L238 362 L265 415 L280 438 L251 444 L238 426 L211 375 Z','#283a43','#78918b',1)
a.path('M160 201 L183 188 L205 205 L224 188 L245 205 L234 276 L219 311 L175 302 L156 268 Z','#344c4d','#9ea47f',1.5)
a.path('M158 202 L201 223 L244 201 L240 235 L201 255 L159 232 Z','url(#cloth)','#bbc8a4',1)
a.path('M157 219 L137 244 L124 285 L103 291 L108 311 L143 301 L169 252 Z','url(#cloth)')
a.path('M242 218 L270 241 L293 261 L308 250 L317 262 L297 285 L277 280 L229 244 Z','url(#cloth)')
a.path('M299 250 L310 244 L322 250 L323 264 L314 272 L303 265 Z','url(#skin)')
sword(a,295,141,24,221)
a.face();a.haircap()
a.path('M151 143 Q182 119 251 147 L271 139 Q236 110 197 106 Q165 111 139 143 Z','url(#cloth)','#b6b793',1.5)
a.path('M169 122 L178 86 L214 102 L237 132 L211 124 Z','#294c4d','#b6b793',1)
a.path('M222 119 Q229 70 267 65 Q261 101 222 119 Z','#bddecc','#5e8d80',1)
a.line(222,120,259,74,'#588b80',1)
a.path('M179 259 L225 269 L229 284 L172 274 Z','url(#gold)');a.jewel(205,273,8)
a.path('M180 208 Q225 224 269 201 Q302 181 335 209 Q309 201 286 219 L324 228 Q274 244 223 232 Z','url(#cloth)')
a.finish('zeph')

# BOLT: lightning archer holding a recurved longbow and energized arrow.
a=Art('#ffe082','#66512a',skin='#c9a78d',hair='#e4d9ad',seed=8)
a.path('M172 190 L134 228 L119 353 L152 333 L167 389 L223 318 L260 255 L237 191 Z','url(#cloth)')
boots(a);a.path('M162 288 L189 304 L181 381 L147 381 Z M206 303 L236 288 L254 380 L218 380 Z','#253645','#8a8b75',1)
a.path('M162 198 L184 190 L200 212 L225 188 L244 208 L232 268 L220 306 L174 302 L158 270 Z','#374759','#ad996d',1)
a.path('M175 202 L228 282 L216 294 L162 217 Z','url(#gold)')
a.path('M161 216 L132 229 L111 252 L122 271 L149 255 L177 238 Z','url(#cloth)')
a.path('M243 211 L270 233 L292 251 L314 251 L314 271 L285 271 L259 254 L230 235 Z','url(#cloth)')
a.path('M297 252 L308 244 L322 250 L324 266 L314 276 L299 269 Z','url(#skin)')
a.path('M112 250 L126 248 L141 257 L136 272 L124 275 L112 265 Z','url(#skin)')
a.face();a.haircap()
a.path('M173 131 L184 119 L209 119 L232 138 L222 143 L205 132 L183 140 Z','url(#gold)')
a.path('M315 109 Q349 143 328 214 L314 261 Q332 320 319 364 L296 398 Q309 355 295 311 L302 265 Q287 214 305 158 Z','#bcb591','#eee0a4',2)
a.path('M315 112 L127 261 L296 397','none','#ffe5a0',1.2)
a.path('M125 261 H348 L334 251 M348 261 L334 271','none','#f6e9b5',2)
a.path('M331 253 L358 261 L331 270 L338 261 Z',a.a,None)
a.path('M297 180 L276 211 L294 207 L279 243 L311 203 L294 205 Z M326 294 L341 318 L327 316 L341 343 L316 314 L327 314 Z',a.a,None)
a.finish('bolt')

# TIDE: temple sentinel, sea-green lamellar and a trident.
a=Art('#8fcfe8','#2a546b',skin='#bd997f',hair='#a2c9d1',seed=9)
cape(a,'M163 194 Q126 221 112 297 L81 439 L143 452 L197 380 L265 452 L317 437 L280 288 Q260 213 232 194 Z')
boots(a);a.path('M154 283 L178 301 L170 390 L143 384 Z M183 304 L209 305 L221 395 L183 402 Z M216 302 L241 281 L257 383 L232 389 Z','url(#cloth)','#b4b99b',1)
a.path('M157 203 L185 189 L217 189 L244 206 L235 276 L219 301 L177 301 L159 275 Z','url(#steel)')
for y in [220,239,258]:a.path(f'M166 {y} Q201 {y+22} 235 {y} L232 {y+13} Q201 {y+34} 167 {y+13} Z','#365b6e','#97b4b9',1)
a.path('M153 200 L127 211 L115 242 L153 255 L172 220 Z M244 201 L270 211 L284 243 L250 256 L227 221 Z','url(#gold)')
a.path('M127 244 L113 280 L100 304 L115 318 L140 292 L156 253 Z M272 245 L294 280 L310 279 L316 302 L285 306 L250 260 Z')
a.path('M299 278 L313 272 L323 282 L322 301 L311 308 L302 301 Z','url(#skin)')
a.path('M309 116 V445 M301 447 H320','none','#b4d3ce',6)
a.path('M309 78 L298 112 L304 132 L303 165 Q271 145 282 102 L267 123 L270 155 L305 181 L311 180 L340 152 L344 120 L332 105 Q340 146 315 165 L315 131 L321 112 Z','url(#steel)','#d5cd9a',1.5)
a.face();a.haircap()
a.path('M170 141 L174 118 L187 128 L200 108 L215 129 L229 117 L233 142 L221 147 L201 135 L179 148 Z','url(#gold)')
a.jewel(201,139,11);a.jewel(201,286,10)
a.path('M69 348 Q90 324 117 339 Q100 335 94 352 Q89 368 65 370 M272 397 Q305 370 335 396 Q312 388 309 405 Q304 424 277 422','none',a.a,2,opacity='.6')
a.finish('tide')

# CINDER: ember sorceress, winged hood and suspended spell-fire.
a=Art('#ffb16c','#7a3e35',skin='#ddbca7',hair='#e9d1b3',seed=10)
a.path('M161 174 Q124 206 113 307 L79 430 L126 443 L165 324 L230 414 L313 440 L274 283 Q264 201 232 176 Z','url(#cloth)')
a.face(long_hair=True)
a.path('M169 199 L186 192 L202 217 L218 193 L240 204 L247 276 L224 311 L273 448 Q199 474 123 443 L177 311 L151 275 Z','url(#cloth)','#c7a078',1)
a.path('M202 236 L184 303 L155 440 L197 455 L218 310 Z','#442c32','#c8aa82',1)
a.path('M169 209 L142 220 L117 269 L86 258 L76 280 L119 299 L141 290 L178 239 Z','url(#cloth)')
a.path('M237 211 L260 224 L283 271 L307 255 L318 275 L280 300 L262 291 L224 238 Z','url(#cloth)')
a.path('M78 261 L92 259 L101 273 L91 284 L77 278 L69 265 Z M305 258 L308 243 L319 238 L330 247 L328 260 L317 274 Z','url(#skin)')
a.haircap()
a.path('M161 164 Q158 130 177 112 L200 79 L224 111 Q245 131 241 164 L223 146 L210 124 L199 117 L184 129 L175 151 Z','url(#cloth)','#d7b58a',1.5)
a.path('M186 126 L201 110 L217 127','none','#e5c094',2)
a.jewel(202,118,9);a.jewel(201,260,14)
for x,y,sz in [(79,226,1),(320,208,.85)]:
 a.group(f'translate({x} {y}) scale({sz})');a.ellipse(0,0,40,42,'url(#halo)',None);a.path('M0 27 Q-30 16 -20 -10 Q-15 -1 -9 0 Q-15 -25 8 -42 Q2 -12 16 -8 Q29 10 15 22 Q8 30 0 27 Z','#f08b4f','#ffd69c',1);a.path('M-3 22 Q-15 6 -2 -11 Q-4 7 7 5 Q14 20 -3 22 Z','#ffe0a4',None);a.end()
a.path('M147 413 Q201 427 251 412','none','#b98e63',1)
a.finish('cinder')

# Beasts use custom silhouettes rather than a shared humanoid rig.
def wolf(name,ice=False):
 a=Art('#a7d8ed' if ice else '#b0bdb4','#254b69' if ice else '#324848',hair='#c4dce2' if ice else '#8d9d9f',seed=11+ice)
 a.path('M132 270 Q67 255 54 206 Q55 281 103 306 L136 299 Z','url(#hair)')
 a.path('M141 302 L138 359 L111 414 L90 432 L117 435 L142 416 L169 353 L179 309 Z','#4c6474')
 a.path('M233 297 L255 350 L282 403 L273 426 L310 426 L307 409 L282 342 L267 288 Z','#3b5366')
 a.path('M116 272 L161 244 L203 247 L225 209 L247 204 L264 249 L289 277 L271 317 L224 337 L176 324 L146 302 L118 315 L97 307 Z','url(#hair)')
 a.path('M123 285 L163 267 L185 280 L201 265 L219 283 L238 262 L253 282 L272 276 L264 300 L227 319 L185 308 L148 286 Z','#7895a2',None)
 a.path('M151 298 L179 314 L176 361 L160 408 L166 425 L129 431 L137 413 L147 355 Z','url(#hair)')
 a.path('M242 306 L265 298 L253 358 L246 415 L260 431 L223 431 L223 416 L223 355 Z','url(#hair)')
 a.path('M207 267 L208 225 L219 195 L232 168 L243 141 L254 184 L273 180 L290 160 L291 201 L315 223 L343 235 L337 255 L316 265 L288 252 L275 282 L252 266 L240 289 L225 269 L214 290 Z','url(#hair)','#091421',2.5)
 a.path('M244 157 L249 190 L236 196 Z M284 174 L283 200 L269 193 Z','#233645',None)
 a.path('M232 208 L256 197 L284 211 L302 235 L285 239 L267 226 L252 234 L238 226 Z','#3b5466',None)
 a.path('M267 213 L289 222 L273 227 Z',a.a,'#101e2a',1)
 a.path('M318 231 L344 235 L338 249 L321 247 Z','#0b1826','#829da5',1)
 a.path('M288 249 L317 254 L329 251 L315 266 L292 263 Z','#0a1424','#7997a1',1)
 a.path('M300 254 L304 266 L310 255 M315 255 L317 262 L322 253','#d4e0d5',None)
 a.path('M218 234 L242 252 L248 272 M227 218 L246 232 M265 184 L262 204','none','#c3d5d2',1,opacity='.65')
 for x,y in [(134,420),(144,420),(233,422),(243,422),(294,418)]:a.path(f'M{x} {y} l-4 10 8 -2 Z','#d2d6ca',None)
 if ice:
  for x,y,h in [(143,263,45),(171,253,59),(197,253,48),(218,234,56),(237,202,29)]:
   a.path(f'M{x-11} {y+9} L{x-5} {y-h} L{x+10} {y-21} L{x+12} {y+5} Z','#569cc4','#b9e7f1',1)
   a.path(f'M{x-5} {y-h} L{x+2} {y+3} L{x+10} {y-21} Z','#a2d8e5',None)
  for x,y in [(90,158),(318,335),(80,366)]:
   for deg in [0,60,120]:
    a.group(f'translate({x} {y}) rotate({deg})');a.line(-9,0,9,0,'#a3dcf1',1);a.end()
 else:
  a.path('M65 385 Q115 363 141 389 M279 152 Q310 132 335 150','none','#80a99d',1.4,opacity='.55')
 a.finish(name)
wolf('wolf');wolf('ice_wolf',True)

# Goblin: hooked ears, cunning expression, scrap mail and cleaver.
a=Art('#b2ce72','#435633',skin='#8ca978',hair='#405146',seed=13)
a.path('M165 312 L188 319 L177 382 L158 420 L131 429 L125 420 L145 399 L147 352 Z M207 318 L233 310 L243 363 L266 408 L276 426 L249 433 L235 419 L218 378 Z','url(#skin)')
a.path('M144 260 L172 230 L214 228 L248 251 L240 311 L204 340 L166 326 L144 294 Z','url(#cloth)')
a.path('M162 257 L186 247 L214 247 L234 264 L224 304 L188 319 L163 299 Z','#4b5151','#b4a87b',1)
a.path('M143 259 L123 281 L108 318 L85 324 L83 343 L116 346 L133 330 L163 278 Z','url(#skin)')
a.path('M246 256 L271 268 L283 298 L308 284 L319 302 L279 325 L263 310 L228 281 Z','url(#skin)')
a.path('M145 258 L125 266 L117 288 L144 300 L165 277 Z','url(#steel)')
a.group('translate(312 290) rotate(20)');a.path('M-5 42 V-94 L31 -118 L39 -44 L8 -34 V42 Z','url(#steel)','#b8bb9c',1.5);a.path('M-5 42 H7 V2 H-5 Z','#5c3b34','#bb9e66',1);a.end()
a.path('M179 215 L174 243 L196 260 L216 241 L214 215 Z','url(#skin)')
a.path('M169 163 L128 135 L142 181 L167 202 M222 165 L273 137 L252 187 L227 203','url(#skin)')
a.path('M168 169 Q195 141 224 167 L235 202 L222 226 L199 239 L174 230 L155 208 Z','url(#skin)')
a.path('M162 184 L182 180 L186 195 L164 197 M210 181 L229 184 L228 198 L210 195','#314533',None)
a.path('M169 192 L182 191 M213 191 L225 193','none','#f0d58a',3)
a.path('M194 190 L180 211 L198 217 L210 207 Z','#a7b983','#495b47',1)
a.path('M175 219 Q199 225 218 215','none','#28372e',2.5)
a.path('M180 220 L185 211 L189 223 M208 219 L213 211 L216 218','#ecdfb3',None)
a.path('M154 179 L167 148 L196 137 L223 146 L238 176 L212 171 L196 156 L174 172 Z','#423f38','#a99d6c',1.5)
a.path('M166 154 L156 133 L178 146 M222 155 L238 136 L232 167','url(#gold)')
a.path('M163 296 L227 291 L235 307 L173 316 Z','url(#gold)');a.jewel(200,305,9)
a.finish('goblin')

# Fire imp: small airborne demon, long clawed limbs and ribbed bat wings.
a=Art('#ff8f68','#713a36',skin='#bb6756',hair='#753e42',seed=14)
a.path('M176 239 Q126 164 76 163 L48 102 L51 230 L77 209 L101 242 L119 218 L153 277 Z','url(#cloth)','#ce8869',1.5)
a.path('M228 236 Q267 159 319 163 L350 103 L348 235 L321 212 L300 246 L278 221 L247 277 Z','url(#cloth)','#ce8869',1.5)
a.path('M54 117 L153 262 M78 166 L119 218 M348 118 L247 263 M319 165 L279 221','none','#c27b68',1)
a.path('M213 325 Q270 363 290 333 Q319 289 337 328 Q333 314 322 320 Q311 335 320 358 L311 350 Q273 390 211 344 Z','url(#cloth)')
a.path('M167 290 L186 307 L176 352 L160 372 L164 392 L140 382 L143 368 L155 334 Z M209 310 L230 294 L245 341 L239 366 L257 382 L232 387 L220 367 L222 343 Z','url(#skin)')
a.path('M171 214 L193 208 L223 212 L241 251 L229 295 L203 322 L173 302 L154 259 Z','url(#skin)')
a.path('M176 239 L199 251 L225 238 L218 273 L201 298 L181 274 Z','#763d42',None)
a.path('M160 232 L139 263 L108 253 L96 272 L140 289 L157 277 L181 246 Z','url(#skin)')
a.path('M232 229 L256 258 L291 242 L303 262 L259 284 L245 277 L216 249 Z','url(#skin)')
a.path('M105 253 L95 239 L88 252 L79 248 L81 267 L99 275 M294 243 L303 229 L309 242 L320 238 L317 258 L301 264','url(#skin)')
a.path('M170 162 Q198 144 226 162 L238 190 L222 218 L198 229 L174 218 L157 190 Z','url(#skin)')
a.path('M173 171 L156 149 L155 119 L170 141 L191 157 M211 156 L233 138 L243 113 L247 146 L226 173','url(#gold)')
a.path('M161 177 L139 169 L152 195 L166 197 M233 176 L257 166 L247 194 L232 199','url(#skin)')
a.path('M169 182 L189 191 L175 196 Z M210 191 L229 180 L225 196 Z','#ffcf8e','#5f3438',1)
a.path('M181 209 L219 206 L200 219 Z','#362a34',None)
a.path('M188 208 L192 214 L197 207 M208 207 L212 213 L216 207','#ffe3b0',None)
a.path('M199 151 L182 133 L196 101 L200 125 L215 136 L208 151 Z','#ec9d64','#ffcb8a',1)
a.path('M74 237 Q57 218 72 193 Q70 209 83 214 Q96 226 84 239 Z M311 225 Q301 209 315 186 Q313 204 325 212 L326 224 Z','#e99360','#ffcf91',1)
a.finish('fire_imp')

# Ancient stone guardian with engraved mineral core.
a=Art('#b5c596','#475850',seed=15)
a.path('M143 322 L179 331 L179 388 L164 432 L116 440 L111 423 L132 390 Z M213 331 L251 321 L269 388 L294 424 L286 442 L238 434 L218 391 Z','url(#steel)','#283542',3)
a.path('M116 217 L143 194 L183 200 L195 232 L178 279 L141 290 L108 264 Z','#657a80','#152535',3)
a.path('M217 203 L257 192 L289 213 L301 252 L272 288 L232 281 L207 239 Z','#73858a','#152535',3)
a.path('M115 260 L148 275 L134 308 L120 339 L122 368 L92 382 L71 362 L76 322 Z','#8b9996','#172b38',3)
a.path('M270 275 L298 258 L323 315 L332 356 L316 378 L286 367 L285 335 L272 311 Z','#6b8185','#172b38',3)
a.path('M151 213 L181 197 L218 197 L249 217 L250 285 L229 337 L175 337 L148 288 Z','#8f9e96','#1b2c39',3)
a.path('M152 222 L180 235 L169 274 L150 288 M249 223 L217 236 L228 274 L249 287 M172 299 L198 289 L226 302 L218 327 L180 327 Z','#5b7177','#2b404a',2)
a.path('M181 240 L204 220 L224 241 L220 276 L199 289 L179 274 Z','#344b4e','#bdcaa0',2)
a.path('M199 230 L210 248 L205 262 L211 271 L198 280 L190 262 Z',a.a,None)
a.path('M165 145 L187 127 L216 129 L238 147 L232 186 L212 205 L180 200 L163 181 Z','#8e9d98','#213542',3)
a.path('M170 155 L193 161 L192 175 L170 170 M207 161 L232 154 L229 171 L209 176','#2a3f48',None)
a.path('M175 165 L188 168 M214 169 L226 165','none',a.a,3)
a.path('M198 160 V183 L207 184 M184 188 L216 187','none','#3c5158',2)
a.path('M178 137 L185 149 L196 141 L213 147 L223 137','none','#c8ceb4',1)
a.path('M132 212 L146 229 L133 243 M271 214 L257 236 L279 251 M106 298 L117 316 L104 331 M292 298 L307 318 L299 337 M148 354 L160 373 L146 389 M236 351 L229 374 L249 400','none','#c1cbb0',1.5)
for x,y in [(130,207),(260,200),(232,332),(119,419)]:
 a.path(f'M{x-12} {y+2} L{x-5} {y-8} L{x+4} {y-5} L{x+11} {y+6} L{x-2} {y+10} Z','#638268',None)
a.finish('stone_golem')

# THUNDER HAWK: great raptor in a heraldic dive, individual feather vanes.
a=Art('#f2d37f','#5c4e37',hair='#95abb6',seed=16)
a.path('M190 243 Q133 173 55 118 L60 152 L45 137 L60 179 L50 167 L70 207 L61 197 L86 236 L82 222 L111 253 L103 252 L147 286 L179 294 Z','url(#hair)','#c0b992',2)
a.path('M210 243 Q268 171 345 118 L339 152 L355 136 L340 178 L351 166 L330 207 L339 196 L315 237 L319 223 L291 253 L299 251 L254 286 L222 294 Z','url(#hair)','#c0b992',2)
for i in range(7):
 x=62+i*13;y=154+i*17
 a.path(f'M{x} {y} L{175-i*3} {262+i*2} L{x+16} {y+8} Z','#334d62','#7592a1',.5)
 a.path(f'M{400-x} {y} L{225+i*3} {262+i*2} L{384-x} {y+8} Z','#334d62','#7592a1',.5)
a.path('M183 295 L159 367 L185 355 L179 381 L200 366 L221 383 L217 352 L241 366 L217 295 Z','url(#hair)','#c2b58b',1.5)
a.path('M173 247 Q197 224 227 248 L230 291 L215 328 L202 340 L180 322 L169 287 Z','url(#hair)')
for y in [266,283,300]:a.path(f'M181 {y} L199 {y+14} L219 {y} L215 {y+15} L200 {y+24} L184 {y+15} Z','#627d8f','#b4bdaf',.7)
a.path('M179 246 L180 222 L195 205 L219 209 L230 224 L223 243 L208 257 L193 266 Z','#c4d1c9','#2d4355',2)
a.path('M201 222 L223 219 L231 230 L219 236 L209 238 Z','#273e50',None)
a.path('M210 224 L223 224 L215 231 Z','#f9db8c',None)
a.path('M222 231 L237 240 L225 255 L223 245 L213 241 Z','url(#gold)')
a.path('M186 219 L174 210 L181 232 L176 244 L190 239 Z','#bed0cd',None)
a.path('M180 317 L172 340 L161 349 M174 337 L178 351 M217 317 L228 340 L240 346 M227 338 L224 353','none','#d2bb7a',4)
a.path('M73 294 L98 266 L90 292 L106 288 L79 327 L87 300 Z M312 280 L294 316 L311 311 L300 345 L329 300 L311 305 Z',a.a,None)
a.finish('thunder_hawk')

# DARK KNIGHT: closed funeral armor, violet deathlight and heavy sword.
a=Art('#9a9aea','#353b69',skin='#808aa6',hair='#63728b',seed=17)
cape(a,'M159 182 Q99 219 89 300 L48 439 L99 425 L104 451 L153 423 L204 387 L254 435 L301 448 L291 425 L352 444 L310 281 Q282 208 237 183 Z')
boots(a);a.path('M157 286 L197 299 L182 387 L148 382 L133 366 Z M204 300 L239 287 L265 371 L239 389 L219 383 Z','#1d2a3f','#727b9d',1.5)
sword(a,303,126,-8,299)
a.path('M128 233 L111 280 L127 323 L151 319 L139 281 L161 250 Z M274 235 L296 270 L306 302 L290 315 L278 293 L249 255 Z','#2f3c51','#7d819b',1.5)
breastplate(a);pauldrons(a)
a.path('M166 150 L176 116 L201 105 L227 121 L236 151 L227 181 L202 203 L176 184 Z','#283950','#8c91ad',1.5)
a.path('M171 150 L195 151 L196 167 L177 163 M207 151 L231 148 L225 164 L207 167','#07101c',None)
a.path('M176 156 L192 160 M212 160 L227 154','none',a.a,2)
a.path('M200 121 L192 155 L201 183 L211 154 Z','url(#steel)')
a.path('M172 129 L156 111 L147 79 L172 101 L182 119 M220 118 L231 99 L255 80 L245 111 L231 134','url(#steel)','#9094ac',1.5)
a.path('M175 183 L185 173 L202 193 L218 174 L226 181 L201 208 Z','#141f33','#9693a7',1)
a.path('M129 206 L117 180 L141 196 L150 181 L161 211 M246 204 L257 180 L265 196 L284 182 L277 213','url(#steel)')
a.jewel(202,235,14)
a.finish('dark_knight')

# FLAME LORD: towering crowned demon, lava-forged armor and execution axe.
a=Art('#f6a06b','#6f292e',skin='#ae6a51',hair='#da9b69',seed=18)
a.path('M159 175 Q90 215 71 300 L45 443 L102 420 L120 450 L168 406 L231 408 L282 447 L307 425 L356 445 L329 281 Q284 199 235 175 Z','url(#cloth)')
a.path('M158 301 L188 320 L176 397 L157 441 L115 447 L128 426 L137 367 Z M209 320 L244 301 L270 369 L279 426 L298 446 L258 447 L232 403 Z','#3e3540','#cb9766',2)
a.path('M143 218 L171 194 L223 194 L255 215 L259 283 L232 328 L174 328 L141 281 Z','#4d3a41','#c09364',2)
a.path('M156 222 L197 243 L243 219 L233 267 L202 290 L164 266 Z','#673e3d','#dda575',1)
a.path('M173 282 L198 298 L224 281 L237 304 L202 323 L164 305 Z','url(#gold)')
a.path('M140 217 L116 243 L96 289 L83 325 L105 339 L123 309 L155 262 Z','#5b3c3e','#cb9266',1.5)
a.path('M255 218 L281 246 L297 286 L319 296 L312 321 L278 303 L244 260 Z','#5b3c3e','#cb9266',1.5)
a.path('M148 206 L122 190 L103 213 L99 244 L138 259 L165 232 Z M247 203 L278 189 L301 214 L306 246 L265 260 L234 230 Z','url(#steel)','#d9a46c',2)
a.path('M111 215 L94 173 L123 197 L133 177 L141 206 M270 202 L275 175 L287 196 L309 172 L297 216','url(#gold)')
a.path('M171 151 L179 124 L200 116 L223 129 L234 155 L225 187 L203 209 L180 189 Z','url(#skin)')
a.path('M181 150 L194 154 L189 165 L177 160 M210 154 L225 149 L228 160 L213 166','#3d2933',None)
a.path('M180 157 L190 160 M214 160 L226 156','none','#ffd396',2.5)
a.path('M191 181 L213 181 L203 191 Z','#4a2c33',None)
a.path('M171 147 L152 127 L138 89 L163 112 L180 126 M220 125 L239 108 L258 78 L251 116 L233 149','url(#gold)','#e0b17b',1.5)
a.path('M176 134 L167 104 L185 116 L199 83 L215 115 L236 99 L225 138 L201 128 Z','url(#gold)')
a.jewel(201,123,13,'#f4aa6d');a.jewel(201,252,20,'#f7ad6f')
a.group('translate(317 278) rotate(-9)');a.path('M-4 -140 H6 V171 H-4 Z','url(#gold)');a.path('M-5 -123 Q-63 -146 -55 -192 Q-78 -176 -75 -136 Q-74 -102 -29 -89 L-5 -97 M6 -123 Q53 -140 62 -186 Q84 -156 72 -126 Q60 -100 7 -92','url(#steel)','#f0b878',2);a.path('M-13 -124 L3 -139 L20 -123 L3 -105 Z','#df744c','#ffc789',1);a.end()
a.path('M79 422 Q56 394 73 366 Q76 390 89 387 Q100 402 95 421 M315 409 Q300 382 318 360 Q315 380 329 390 L333 415','#c96c48','#f1b377',1)
a.finish('boss_flame_lord')

# STORM WITCH: sweeping crescent hat, thunder staff and embroidered storm robes.
a=Art('#c4a6f0','#503c73',skin='#d6bdc7',hair='#d2d5e7',seed=19)
a.path('M159 181 Q112 213 99 307 L53 435 L103 422 L128 451 L180 353 L226 407 L280 450 L333 426 L300 309 Q279 212 234 183 Z','url(#cloth)')
a.face(long_hair=True)
a.path('M165 199 L185 190 L202 213 L219 192 L242 202 L248 276 L225 308 L284 450 Q203 474 117 446 L174 308 L151 271 Z','url(#cloth)','#c7b4d4',1.5)
a.path('M201 228 L180 308 L150 444 L201 459 L222 310 Z','#2c2a49','#bd9fca',1)
a.path('M158 211 L132 232 L107 274 L84 266 L77 286 L118 306 L137 295 L174 239 Z','url(#cloth)','#a997b7',1)
a.path('M240 208 L262 227 L286 268 L306 260 L316 279 L280 302 L263 290 L226 238 Z','url(#cloth)','#a997b7',1)
a.path('M79 267 L90 265 L101 276 L91 290 L78 285 L69 275 Z M304 261 L313 250 L325 255 L332 269 L320 281 L310 279 Z','url(#skin)')
a.haircap()
a.path('M117 147 Q145 123 178 121 L197 65 Q211 57 231 66 L213 81 L233 122 Q270 125 290 145 Q244 166 201 155 Q151 165 117 147 Z','url(#cloth)','#c7afcf',2)
a.path('M173 129 Q201 140 238 130 L234 120 Q201 128 178 120 Z','url(#gold)')
a.jewel(201,130,11);a.jewel(201,255,17)
a.path('M89 177 L83 446','none','#c4afcc',6)
a.path('M90 179 Q45 153 72 112 L92 91 L89 115 Q68 133 87 149 Q111 137 105 117 L108 104 Q143 148 90 179 Z','url(#steel)','#d6c2df',1.5)
a.jewel(91,139,17,'#dcc4f7')
a.path('M307 245 L290 221 L307 214 L284 182 L320 206 L307 217 L330 244 Z M99 103 L117 72 L102 76 L117 45 L84 85 L99 81 Z',a.a,None)
a.ellipse(315,232,33,32,'none',a.a,.7,opacity='.5')
a.path('M315 197 L315 266 M280 232 H350','none',a.a,.7,opacity='.4')
a.path('M154 421 Q202 440 252 420 M160 410 Q201 426 245 409','none','#b4a0bf',1)
a.finish('boss_storm_witch')

expected={k for k,v in CAT['CharacterData'].items() if not v.get('image')}|set(CAT['EnemyData'])
assert {p.stem for p in OUT.glob('*.svg')} == expected
for p in OUT.glob('*.svg'):
 root=ET.parse(p).getroot(); assert root.attrib['viewBox']=='0 0 400 500'
print(f'Created and XML-validated {len(expected)} original SVG portraits in {OUT}')
