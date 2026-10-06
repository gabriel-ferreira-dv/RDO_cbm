import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

const String zonaUtmNomePadrao = 'UTM24S';
const String zonaUtmDefPadrao =
    '+proj=utm +zone=24 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs';

proj4.Projection _zona(String nome, String def) =>
    proj4.Projection.get(nome) ?? proj4.Projection.add(nome, def);

LatLng utmParaLatLng(
  double e,
  double n, {
  String zoneName = zonaUtmNomePadrao,
  String zoneDef = zonaUtmDefPadrao,
}) {
  final wgs84 = proj4.Projection.get('EPSG:4326')!;
  final pt = _zona(zoneName, zoneDef).transform(wgs84, proj4.Point(x: e, y: n));
  return LatLng(pt.y, pt.x);
}

proj4.Point latLngParaUtm(
  LatLng ll, {
  String zoneName = zonaUtmNomePadrao,
  String zoneDef = zonaUtmDefPadrao,
}) {
  final wgs84 = proj4.Projection.get('EPSG:4326')!;
  return wgs84.transform(_zona(zoneName, zoneDef), proj4.Point(x: ll.longitude, y: ll.latitude));
}
