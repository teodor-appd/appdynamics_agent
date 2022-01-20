/*
 * Copyright (c) 2021. AppDynamics LLC and its affiliates.
 * All rights reserved.
 *
 */

import 'package:appdynamics_mobilesdk/appdynamics_mobilesdk.dart';
import 'package:appdynamics_mobilesdk/src/globals.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class TrackedWidget {
  late String widgetName;

  late String uuidString;

  late String startDate;

  String? endDate;

  TrackedWidget({
    required this.widgetName,
    required this.uuidString,
    required this.startDate,
    this.endDate,
  });

  TrackedWidget.fromJson(Map<String, dynamic> json) {
    widgetName = json["widgetName"];
    uuidString = json["uuidString"];
    startDate = json["startDate"];
    endDate = json["endDate"];
  }

  Map<String, dynamic> toJson() {
    return {
      'widgetName': widgetName,
      'uuidString': uuidString,
      'startDate': startDate,
      'endDate': endDate,
    };
  }
}

/// Used for manually tracking activities throughout the app.
///
/// The available methods permit specifying the start and end of a Flutter
/// widget to be reflected as an app screen in the controller.
///
/// Warning: Be sure to be using unique widget names. Duplicate names might
/// result in unexpected behavior.
///
/// For apps using named routes, see [NavigationObserver].
///
/// ```dart
/// import 'package:appdynamics_mobilesdk/appdynamics_mobilesdk.dart';
/// import 'package:flutter/cupertino.dart';
/// import 'package:flutter/material.dart';
///
/// class CheckoutPage extends StatefulWidget {
///   const CheckoutPage({Key? key}) : super(key: key);
///
///   static String screenName = "Checkout Page";
///
///   @override
///   _CheckoutPageState createState() => _CheckoutPageState();
/// }
///
/// class _CheckoutPageState extends State<CheckoutPage> {
///   @override
///   void initState() async {
///     super.initState();
///     await WidgetTracker.instance.trackWidgetStart(CheckoutPage.screenName);
///   }
///
///   _backToMainScreen() async {
///     await WidgetTracker.instance.trackWidgetEnd(CheckoutPage.screenName);
///     Navigator.pop(context);
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Center(
///         child:
///         Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
///           ElevatedButton(
///             child: const Text('Proceed'),
///             onPressed: _backToMainScreen,
///           )
///         ]));
///   }
/// }
/// ```
class WidgetTracker {
  final Map<String, TrackedWidget> trackedWidgets = {};

  WidgetTracker._privateConstructor();

  static final WidgetTracker _instance = WidgetTracker._privateConstructor();

  static WidgetTracker get instance => _instance;

  /// Tracks when a widget has started.
  ///
  /// May throw [Exception] on native platform contingency.
  Future<void> trackWidgetStart(String widgetName) async {
    try {
      final uuidString = const Uuid().v1();
      final startDate = DateTime.now().toIso8601String();
      final trackedWidget = TrackedWidget(
          widgetName: widgetName, uuidString: uuidString, startDate: startDate);

      await channel.invokeMethod<void>(
          'trackPageStart', trackedWidget.toJson());

      trackedWidgets[trackedWidget.widgetName] = trackedWidget;
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Tracks when a widget has ended.
  ///
  /// If the widget doesn't exist, it doesn't do anything.
  ///
  /// May throw [Exception] on native platform contingency.
  Future<void> trackWidgetEnd(String widgetName) async {
    try {
      final trackedWidget = trackedWidgets[widgetName];

      if (trackedWidget == null) {
        return;
      }

      final endDate = DateTime.now().toIso8601String();
      trackedWidget.endDate = endDate;

      await channel.invokeMethod<void>('trackPageEnd', trackedWidget.toJson());

      trackedWidgets.remove(trackedWidget.widgetName);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }
}
