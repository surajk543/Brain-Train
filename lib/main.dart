import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/typography.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  runApp(const BrainTrainApp());
}
