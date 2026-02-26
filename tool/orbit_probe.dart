import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;

class P {final double x;final double y; const P(this.x,this.y);} 

void main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : '../miniapp-orbit-code.png';
  final b = await File(path).readAsBytes();
  final d = img.decodeImage(b);
  if (d==null){print('decode image fail'); return;}
  var image = d;
  final side = math.min(image.width, image.height);
  final left = ((image.width - side) / 2).round();
  final top = ((image.height - side) / 2).round();
  image = img.copyCrop(image, x:left,y:top,width:side,height:side);
  if (side > 960) {
    image = img.copyResize(image,width:960,height:960,interpolation: img.Interpolation.average);
  }
  final s = math.min(image.width, image.height).toDouble();
  final center = P(image.width/2.0,image.height/2.0);
  final baseRadius = s*0.218;
  final zoneWidth = s*0.047;
  final zoneGap = s*0.013;
  final activeLen = zoneWidth-zoneGap;

  double luma(img.Pixel p)=> p.r*0.299+p.g*0.587+p.b*0.114;
  double threshold(){
    var sum=0.0; var count=0;
    final step = math.max(1, image.width~/180);
    for (var y=0;y<image.height;y+=step){
      for (var x=0;x<image.width;x+=step){sum += luma(image.getPixel(x,y)); count++;}
    }
    final mean = count==0?150:sum/count;
    return (mean*0.82).clamp(70,190);
  }
  final th = threshold();
  bool isDark(double x,double y){
    final ix=x.round(), iy=y.round();
    if(ix<0||iy<0||ix>=image.width||iy>=image.height) return false;
    return luma(image.getPixel(ix,iy)) <= th;
  }
  P pt(double angleDeg,double r){
    final a = angleDeg*math.pi/180.0;
    return P(center.x + math.cos(a)*r, center.y + math.sin(a)*r);
  }
  double disk(P c,double r){
    final rr = r.round().clamp(1,48);
    var dark=0,count=0;
    for (var y=-rr;y<=rr;y++){
      for (var x=-rr;x<=rr;x++){
        if(x*x+y*y>rr*rr) continue;
        if(isDark(c.x+x,c.y+y)) dark++;
        count++;
      }
    }
    return count==0?0:dark/count;
  }

  String bitsToHex(List<int> bits,int start,int n){
    final sb=StringBuffer();
    final end=start+n;
    for (var i=start;i<end;i+=4){
      var nib=0;
      for (var b=0;b<4;b++){nib=(nib<<1)|bits[i+b];}
      sb.write(nib.toRadixString(16));
    }
    return sb.toString();
  }

  String checksumHex(String id){
    var acc=0;
    for (var i=0;i<id.length;i++){
      final n = int.tryParse(id[i],radix:16)??0; acc ^= (n&0xF);
    }
    return (acc&0xF).toRadixString(16);
  }

  int valid=0;
  for (var deg=0.0; deg<360; deg+=2){
    final bits=<int>[];
    for (var ray=0; ray<36; ray++){
      if (ray==0||ray==12||ray==24) continue;
      final angle = ray*10.0 + deg - 90.0;
      for (var z=0; z<4; z++){
        final r = baseRadius + z*zoneWidth + activeLen*0.5;
        final p = pt(angle,r);
        final d = disk(p, math.max(1.2, image.width*0.010));
        bits.add(d >= 0.52 ? 1 : 0);
      }
    }
    if(bits.length<132) continue;
    final id = bitsToHex(bits,0,128);
    final cs = bitsToHex(bits,128,4);
    final expect = checksumHex(id);
    final ones = bits.where((e)=>e==1).length;
    if (cs==expect){
      valid++;
      print('deg=$deg id=$id cs=$cs ones=$ones');
    }
  }
  print('validCount=$valid');
}
