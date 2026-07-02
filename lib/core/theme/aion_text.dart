import 'package:flutter/painting.dart';

abstract final class AionText {
  static const _ui = 'Manrope';
  static const _mono = 'JetBrainsMono';

  static const display = TextStyle(
    fontFamily: _ui,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.64,
    height: 1.1,
  );

  static const h1 = TextStyle(
    fontFamily: _ui,
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.50,
    height: 1.15,
  );

  static const h2 = TextStyle(
    fontFamily: _ui,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.22,
    height: 1.25,
  );

  static const body = TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  static const bodySm = TextStyle(
    fontFamily: _ui,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const cardTitle = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const label = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const button = TextStyle(
    fontFamily: _ui,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  static const chip = TextStyle(
    fontFamily: _ui,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.53,
  );

  static const priorityBig = TextStyle(
    fontFamily: _ui,
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.53,
  );

  static const prioritySm = TextStyle(
    fontFamily: _ui,
    fontSize: 8.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.43,
  );

  static const key = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.11,
  );

  static const caption = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.54,
  );

  static const time = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );
}
