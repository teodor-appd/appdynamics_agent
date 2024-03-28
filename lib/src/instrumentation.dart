/*
 * Copyright (c) 2022. AppDynamics LLC and its affiliates.
 * All rights reserved.
 *
 */

// TODO: Extract methods into files when static extensions are supported.
// https://github.com/dart-lang/language/issues/723

import 'dart:async';

import 'package:appdynamics_agent/appdynamics_agent.dart';
import 'package:appdynamics_agent/src/session_frame.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'
    show rootBundle, PlatformException, MethodCall;

import 'crash_report.dart';
import 'globals.dart';

enum BreadcrumbVisibility {
  crashesOnly,
  crashesAndSessions,
}

enum ErrorSeverityLevel {
  /// An error happened, but it did not cause a problem.
  info,

  /// An error happened, but the app recovered gracefully.
  warning,

  /// An error happened and caused problems to the app.
  critical,
}

/// Main class used to interact with the AppDynamics agent.
///
/// This class provides several methods to instrument your app, including:
///
/// - Initializing the agent with the right configuration and key;
/// - Reporting timers, errors, session frames, custom metrics;
/// - Shutting down and restarting agent;
/// - Changing app key dynamically;
/// - Tracking calls, and starting new sessions.
class Instrumentation {
  Instrumentation._();

  static const maxUserDataStringLength = 2048;

  static _initializeCrashCallback(CrashReportCallback callback) {
    Future<dynamic> crashReportingHandler(MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'onCrashReported':
          final rawMaps = methodCall.arguments as List<dynamic>;
          final summaries = rawMaps
              .map((map) =>
                  CrashReportSummary.fromJson(Map<String, dynamic>.from(map)))
              .toList();
          callback(summaries);
      }
    }

    channel.setMethodCallHandler(crashReportingHandler);
  }

  /// Initializes the agent.
  ///
  /// The agent does not automatically start with your application. You can
  /// initialize the agent using the app key shown in your UI controller.
  /// This has to be done near your application's entry point before any other
  /// initialization routines in your application.
  ///
  /// Once initialized, further calls to [Instrumentation.start] have no effect
  /// on the agent.
  ///
  /// **Warning**: Be careful when using other 3rd party packages. Based on the
  /// order of initialization, conflicts might occur.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// try {
  ///   AgentConfiguration config = AgentConfiguration(
  ///       appKey: appKey,
  ///       loggingLevel: LoggingLevel.verbose,
  ///       collectorURL: collectorURL);
  ///   await Instrumentation.start(config);
  /// } catch (e) {
  ///   // handle exception
  /// }
  /// ```
  static Future<void> start(AgentConfiguration config) async {
    String version = await rootBundle
        .loadString('packages/appdynamics_agent/version.txt', cache: false);
    String type = "Flutter";

    final crashCallback = config.crashReportCallback;
    if (crashCallback != null) {
      _initializeCrashCallback(crashCallback);
    }

    Map<String, dynamic> arguments = {
      "appKey": config.appKey,
      "applicationName": config.applicationName,
      "loggingLevel": config.loggingLevel.index,
      "collectorURL": config.collectorURL,
      "screenshotURL": config.screenshotURL,
      "screenshotsEnabled": config.screenshotsEnabled,
      "crashReportingEnabled": config.crashReportingEnabled,
      "anrDetectionEnabled":
          true, // hardcoded until it's implemented on Android agent too
      "anrStackTraceEnabled":
          true, // hardcoded until it's implemented on Android agent too
      "version": version,
      "type": type,
    }..removeWhere((key, value) => value == null);

    try {
      await channel.invokeMethod<void>('start', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Times events by using custom timers that span across multiple methods.
  ///
  /// Timer names can contain only alphanumeric characters and spaces.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// Future<void> doCheckout() async {
  ///  final checkoutTimerName = "Time spent on checkout";
  ///
  ///  try {
  ///    await Instrumentation.startTimer(checkoutTimerName);
  ///    await someCheckoutService();
  ///    await someOtherLongTask();
  ///  } finally {
  ///    await Instrumentation.stopTimer(checkoutTimerName);
  ///  }
  /// }
  /// ```
  static Future<void> startTimer(String name) async {
    try {
      await channel.invokeMethod<void>('startTimer', name);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Stops timer started with [Instrumentation.startTimer].
  ///
  /// Method might throw [Exception].
  static Future<void> stopTimer(String name) async {
    try {
      await channel.invokeMethod<void>('stopTimer', name);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Leaves a breadcrumb that will appear in a crash report and optionally,
  /// on the session.
  ///
  /// Call this when something interesting happens in your application.
  /// The breadcrumb will be included in different reports depending on the
  /// `mode`. Each crash report displays the most recent 99 breadcrumbs.
  ///
  /// If you would like it to appear also in sessions, use
  /// [BreadcrumbVisibility.crashesAndSessions].
  ///
  /// Use [breadcrumb] to include a message in the crash report and sessions.
  /// If it's longer than 2048 characters, it will be truncated.
  /// If it's empty, no breadcrumb will be recorded.
  /// Use [mode] with a value of [BreadcrumbVisibility]. If invalid, defaults
  /// to [BreadcrumbVisibility.crashesOnly].
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// Future<void> showSignUp() async {
  ///   try {
  ///     await Instrumentation.leaveBreadcrumb("Pushing Sign up screen.",
  ///      BreadcrumbVisibility.crashesAndSessions);
  ///     await pushSignUpScreen();
  ///   } catch (e) {
  ///     // handle exception
  ///   }
  /// }
  /// ```
  static Future<void> leaveBreadcrumb(
    String breadcrumb,
    BreadcrumbVisibility mode,
  ) async {
    try {
      final arguments = {"breadcrumb": breadcrumb, "mode": mode.index};
      await channel.invokeMethod<void>('leaveBreadcrumb', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Reports an `Exception` that was caught.
  ///
  /// This can be called in catch blocks to report unexpected exceptions, that
  /// you want to track.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// try {
  ///   await jsonDecode("invalid/exception/json");
  /// } on FormatException catch (e) {
  ///   await Instrumentation.reportException(e,
  ///       severityLevel: ErrorSeverityLevel.warning);
  /// }
  /// ```
  static Future<void> reportException(Exception exception,
      {ErrorSeverityLevel severityLevel = ErrorSeverityLevel.warning,
      StackTrace? stackTrace}) async {
    try {
      final arguments = {
        "message": exception.toString(),
        "severity": severityLevel.index,
        "stackTrace": stackTrace?.toString()
      };
      await channel.invokeMethod<void>('reportError', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Reports an `Error` that was caught. Includes the error's stack trace.
  ///
  /// This can be called in catch blocks to report unexpected errors that you
  /// want to track.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// try {
  ///    final myMethod = null;
  ///    myMethod();
  ///  } on NoSuchMethodError catch (e) {
  ///    await Instrumentation.reportError(e,
  ///        severityLevel: ErrorSeverityLevel.critical);
  ///  }
  /// ```
  static Future<void> reportError(Error error,
      {ErrorSeverityLevel severityLevel = ErrorSeverityLevel.warning}) async {
    try {
      final arguments = {
        "message": error.toString(),
        "stackTrace": error.stackTrace?.toString(),
        "severity": severityLevel.index
      };
      await channel.invokeMethod<void>('reportError', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Reports a custom message with a corresponding severity and sometimes with
  /// a stack trace.
  ///
  /// Useful in case you are handling errors that don't match [reportError] nor
  /// [reportException].
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// try {
  ///   // Call custom API.
  /// } on CustomError catch (e, stackTrace) {
  ///   await Instrumentation.reportMessage(
  ///     e.toString(),
  ///     severityLevel: ErrorSeverityLevel.info,
  ///     stackTrace: stackTrace
  ///   );
  /// }
  /// ```
  static Future<void> reportMessage(String message,
      {ErrorSeverityLevel severityLevel = ErrorSeverityLevel.warning,
      StackTrace? stackTrace}) async {
    try {
      final arguments = {
        "message": message,
        "severity": severityLevel.index,
        "stackTrace": stackTrace?.toString()
      };
      await channel.invokeMethod<void>('reportError', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Sets a key-value pair identifier that will be included in all snapshots.
  /// This identifier can be used to add the `String` types.
  ///
  /// The [key] must be unique across your application.
  /// The [key] namespace is distinct for each user data type.
  /// Re-using the same [key] overwrites the previous [value].
  /// The [key] is limited to [maxUserDataStringLength] characters.
  ///
  /// A [value] of `null` will clear the data.
  /// The [value] is also limited to [maxUserDataStringLength] characters.
  ///
  /// This information is not persisted across application runs. Once the
  /// application is destroyed, user data is cleared.
  ///
  /// Data can be removed via [removeUserData].
  ///
  /// Method might throw [Exception].
  static Future<void> setUserData(
    String key,
    String? value,
  ) async {
    try {
      if (value == null) {
        removeUserData(key);
        return;
      }

      final arguments = {"key": key, "value": value};
      await channel.invokeMethod<void>('setUserData', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Removes the `String` corresponding to a [key] set with [setUserData].
  ///
  /// Method might throw [Exception].
  static Future<void> removeUserData(
    String key,
  ) async {
    try {
      await channel.invokeMethod<void>('removeUserData', key);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Sets a key-value pair identifier that will be included in all snapshots.
  /// This identifier can be used to add the `double` types.
  ///
  /// The [key] must be unique across your application.
  /// The [key] namespace is distinct for each user data type.
  /// Re-using the same [key] overwrites the previous [value].
  /// The [key] is limited to [maxUserDataStringLength] characters.
  ///
  /// A [value] of `null` will clear the data.
  /// The [value] is also limited to [maxUserDataStringLength] characters.
  ///
  /// This information is not persisted across application runs. Once the
  /// application is destroyed, user data is cleared.
  ///
  /// Data can be removed via [removeUserDataDouble].
  ///
  /// Method might throw [Exception].
  static Future<void> setUserDataDouble(
    String key,
    double? value,
  ) async {
    try {
      if (value == null) {
        removeUserDataDouble(key);
        return;
      }

      final arguments = {"key": key, "value": value};
      await channel.invokeMethod<void>('setUserDataDouble', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Removes the `double` corresponding to a [key] set with
  /// [setUserDataDouble].
  ///
  /// Method might throw [Exception].
  static Future<void> removeUserDataDouble(
    String key,
  ) async {
    try {
      await channel.invokeMethod<void>('removeUserDataDouble', key);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Sets a key-value pair identifier that will be included in all snapshots.
  /// This identifier can be used to add the `int` types.
  ///
  /// The [key] must be unique across your application.
  /// The [key] namespace is distinct for each user data type.
  /// Re-using the same [key] overwrites the previous [value].
  /// The [key] is limited to [maxUserDataStringLength] characters.
  ///
  /// A [value] of `null` will clear the data.
  /// The [value] is also limited to [maxUserDataStringLength] characters.
  ///
  /// This information is not persisted across application runs. Once the
  /// application is destroyed, user data is cleared.
  ///
  /// Data can be removed via [removeUserDataInt].
  ///
  /// Method might throw [Exception].
  static Future<void> setUserDataInt(
    String key,
    int? value,
  ) async {
    try {
      if (value == null) {
        removeUserDataInt(key);
        return;
      }

      final arguments = {"key": key, "value": value};
      await channel.invokeMethod<void>('setUserDataLong', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Removes the `int` corresponding to a [key] set with [setUserDataInt].
  ///
  /// Method might throw [Exception].
  static Future<void> removeUserDataInt(
    String key,
  ) async {
    try {
      await channel.invokeMethod<void>('removeUserDataLong', key);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Sets a key-value pair identifier that will be included in all snapshots.
  /// This identifier can be used to add the `bool` types.
  ///
  /// The [key] must be unique across your application.
  /// The [key] namespace is distinct for each user data type.
  /// Re-using the same [key] overwrites the previous [value].
  /// The [key] is limited to [maxUserDataStringLength] characters.
  ///
  /// A [value] of `null` will clear the data.
  /// The [value] is also limited to [maxUserDataStringLength] characters.
  ///
  /// This information is not persisted across application run. Once the
  /// application is destroyed, user data is cleared.
  ///
  /// Data can be removed via [removeUserDataBool].
  ///
  /// Method might throw [Exception].
  static Future<void> setUserDataBool(
    String key,
    bool? value,
  ) async {
    try {
      if (value == null) {
        removeUserDataBool(key);
        return;
      }

      final arguments = {"key": key, "value": value};
      await channel.invokeMethod<void>('setUserDataBoolean', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Removes the `bool` corresponding to a [key] set with [setUserDataBool].
  ///
  /// Method might throw [Exception].
  static Future<void> removeUserDataBool(
    String key,
  ) async {
    try {
      await channel.invokeMethod<void>('removeUserDataBoolean', key);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Sets a key-value pair identifier that will be included in all snapshots.
  /// This identifier can be used to add the `DateTime` types.
  ///
  /// The [key] must be unique across your application.
  /// The [key] namespace is distinct for each user data type.
  /// Re-using the same [key] overwrites the previous [value].
  /// The [key] is limited to [maxUserDataStringLength] characters.
  ///
  /// A [value] of `null` will clear the data.
  /// The [value] is also limited to [maxUserDataStringLength] characters.
  ///
  /// This information is not persisted across application runs. Once the
  /// application is destroyed, user data is cleared.
  ///
  /// Data can be removed via [removeUserDataDateTime].
  ///
  /// Method might throw [Exception].
  static Future<void> setUserDataDateTime(
    String key,
    DateTime? value,
  ) async {
    try {
      if (value == null) {
        removeUserDataDateTime(key);
        return;
      }

      final arguments = {"key": key, "value": value.millisecondsSinceEpoch};
      await channel.invokeMethod<void>('setUserDataDate', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Removes the `DateTime` corresponding to a [key] set with
  /// [setUserDataDateTime].
  ///
  /// Method might throw [Exception].
  static Future<void> removeUserDataDateTime(
    String key,
  ) async {
    try {
      await channel.invokeMethod<void>('removeUserDataDate', key);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Starts and returns a [SessionFrame] object.
  ///
  /// You can use the Session Frame API to create session frames that will
  /// appear in the session activity. Session frames provide context for what
  /// the user is doing during a session. With this API, you can improve the
  /// names of user screens and chronicle user flows within a business context.
  ///
  /// The following are common use cases for the SessionFrame API:
  ///
  /// * One screen performs multiple functions and you want more granular
  ///  tracking of the individual functions.
  /// * A user flow spans multiple screens or user interactions.
  ///  For example, you could use the API to create the session frames
  ///  "Login", "Product Selection", and "Purchase" to follow the user's flow
  ///  for purchases.
  /// * You want to capture dynamic information based on user interactions to
  /// name session frames, such as an order ID.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// class ShoppingCart {
  ///   late SessionFrame _sessionFrame;
  ///   late String _orderId;
  ///
  /// void onCheckoutCartButtonClick() async {
  ///   // The checkout starts when the user clicks the checkout button.
  ///   // This may be after they have updated quantities of items in their
  ///   // cart, etc.
  ///   _sessionFrame = await Instrumentation.startSessionFrame("Checkout");
  /// }
  ///
  /// void onConfirmOrderButtonClick() {
  ///   // Once they have confirmed payment info and shipping information,
  ///   // and they are clicking the "Confirm" button to start the backend
  ///   // process of checking out, we may know more information about the
  ///   // order itself, such as an order ID.
  ///   _sessionFrame.updateName("Checkout: Order ID {this.orderId}");
  /// }
  ///
  /// void onProcessOrderComplete() {
  ///   // Once the order is processed, the user is done "checking out" so we
  ///   // end the session frame.
  ///   _sessionFrame.end();
  /// }
  ///
  /// void onCheckoutCancel() {
  ///   // If they cancel or go back, you'll want to end the session frame also,
  ///   // or else it will be left open and appear to have never ended.
  ///   _sessionFrame.end();
  /// }
  /// ```
  static Future<SessionFrame> startSessionFrame(
    String sessionFrameName,
  ) async {
    try {
      final sessionFrame = createSessionFrame();
      final arguments = {"name": sessionFrameName, "id": sessionFrame.id};
      await channel.invokeMethod<void>('startSessionFrame', arguments);
      return sessionFrame;
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Unblocks screenshot capture if it is currently blocked, otherwise this has
  /// no effect. Returns a `Future` which resolves when screenshots are
  /// effectively unblocked.
  ///
  /// If screenshots are disabled through
  /// [AgentConfiguration.screenshotsEnabled] or through the controller UI, this
  /// method has no effect.
  ///
  /// If screenshots are set to manual mode in the controller UI, this method
  /// unblocks for manual mode only.
  ///
  /// **WARNING:** This will unblock capture for the entire app.
  ///
  /// The user is expected to manage any possible nesting issues that may occur
  /// if blocking and unblocking occur in different code paths.
  ///
  /// Method might throw [Exception].
  ///
  /// See [Instrumentation.blockScreenshots].
  static Future<void> unblockScreenshots() async {
    try {
      await channel.invokeMethod<void>('unblockScreenshots');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Blocks screenshot capture if it is currently unblocked; otherwise this
  /// has no effect. Returns a `Future` which resolves when screenshots are
  /// effectively blocked.
  ///
  /// If screenshots are disabled through
  /// [AgentConfiguration.screenshotsEnabled] or through the controller UI, this
  /// method has no effect.
  ///
  /// **WARNING:**  This will block capture for the entire app.
  ///
  /// The user is expected to manage any possible nesting issues that may
  /// occur if blocking and unblocking occur in different code paths.
  ///
  /// Method might throw [Exception].
  ///
  /// See [Instrumentation.unblockScreenshots].
  static Future<void> blockScreenshots() async {
    try {
      await channel.invokeMethod<void>('blockScreenshots');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Returns a `bool` that specifies whether screenshot capturing is blocked.
  ///
  /// Method might throw [Exception].
  static Future<bool> screenshotsBlocked() async {
    try {
      final result = await channel.invokeMethod<bool>('screenshotsBlocked');
      return result!;
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Asynchronously takes a screenshot of the current screen.
  ///
  /// If screenshots are disabled through
  /// [AgentConfiguration.screenshotsEnabled] or through the controller UI, this
  /// method does nothing.
  ///
  /// This will capture everything, including personal information, so you must
  /// be cautious of when to take the screenshot.
  ///
  /// These screenshots will show up in the Sessions screen for this user.
  ///
  /// The screenshots are taken on a background thread, compressed, and only
  /// non-redundant parts are uploaded, so it is safe to take many of these
  /// without impacting the performance of your application.
  ///
  /// Method might throw [Exception].
  static Future<void> takeScreenshot() async {
    try {
      await channel.invokeMethod<void>('takeScreenshot');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Allows reporting numeric values associated with a metric [name]. For
  /// example, to track the number of times your users clicked the checkout
  /// button.
  ///
  /// [name] should contain only alphanumeric characters and spaces.
  /// Illegal characters shall be replaced by their ASCII hex value.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// import 'package:appdynamics_agent/appdynamics_agent.dart';
  /// import 'package:flutter/material.dart';
  ///
  /// class App extends StatelessWidget {
  ///   _finishCheckout() {
  ///     Instrumentation.reportMetric(name: "Checkout Count", value: 1);
  ///     // rest of the checkout logic
  ///   }
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     return Scaffold(
  ///       appBar: AppBar(title: Text("Checkout screen")),
  ///       body: Center(
  ///         child:
  ///             ElevatedButton(
  ///               child: Text('Checkout'),
  ///               onPressed: _finishCheckout,
  ///             )
  ///     ));
  /// }
  /// ```
  static Future<void> reportMetric({
    required String name,
    required int value,
  }) async {
    try {
      final arguments = {"name": name, "value": value};
      await channel.invokeMethod<void>('reportMetric', arguments);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Blocks sending beacons to the collector.
  ///
  /// No data will come from the agent while shut down. All other activities of
  /// the agent will continue, except for event sending.
  ///
  /// Method might throw [Exception].
  ///
  /// See also [restartAgent].
  static Future<void> shutdownAgent() async {
    try {
      await channel.invokeMethod<void>('shutdownAgent');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Restarts sending beacons to the collector.
  ///
  /// Data will start flowing from the agent immediately. No change will occur
  /// if the [shutdownAgent] call has not been made.
  ///
  /// Method might throw [Exception].
  ///
  /// See also [shutdownAgent].
  static Future<void> restartAgent() async {
    try {
      await channel.invokeMethod<void>('restartAgent');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Starts next session and ends the current session.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// Future<void> checkout(dynamic data) async {
  ///   try {
  ///     final response = http.post("https://server.com/checkout", data);
  ///     await Instrumentation.startNextSession();
  ///   } catch (e) {
  ///     // handle exception
  ///   }
  /// }
  /// ```
  static Future<void> startNextSession() async {
    try {
      await channel.invokeMethod<void>('startNextSession');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Reports that a method call has started.
  ///
  /// Only [StandardMessageCodec] types are accepted as [methodArgs]:
  /// null, bools, nums, Strings, Uint8Lists, Int32Lists, Int64Lists,
  /// Float64Lists, Lists of supported values, Maps from supported values to
  /// supported values.
  ///
  /// Method might throw [Exception].
  ///
  /// ```dart
  /// void main() async {
  ///   final myURL = "http://www.mysite.com/news";
  ///   final news = await Instrumentation.trackCall(
  ///     className: "MainScreen",
  ///     methodName: "getNews",
  ///     methodArgs: [myURL],
  ///     methodBody: () async {
  ///       final result = await get(myURL);
  ///       return result;
  ///   });
  /// }
  /// ```
  static Future<T?> trackCall<T>({
    required String className,
    required String methodName,
    required FutureOr<T> Function() methodBody,
    dynamic methodArgs,
    String? uniqueCallId,
  }) async {
    final callId = uniqueCallId ?? UniqueKey().toString();
    final args = {
      "callId": callId,
      "className": className,
      "methodName": methodName,
      "methodArgs": methodArgs
    };

    try {
      await channel.invokeMethod<void>('beginCall', args);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }

    FutureOr<T> onSuccess(dynamic result) async {
      final args = {"callId": callId, "result": result};
      await channel.invokeMethod<void>('endCallWithSuccess', args);
      return result;
    }

    Future<T?> onError(dynamic e) async {
      var error = <String, String>{};

      if (e is Error) {
        error["stackTrace"] = e.stackTrace.toString();
        error["message"] = "Error";
      } else {
        error["message"] = e.toString();
      }

      final args = {"callId": callId, "error": error};
      await channel.invokeMethod<void>('endCallWithError', args);
      return null;
    }

    try {
      final callback = methodBody();
      if (callback is Future<T>) {
        final res = await callback;
        return onSuccess(res);
      } else {
        return onSuccess(callback);
      }
    } catch (e) {
      return onError(e);
    }
  }

  /// Changes the app key after initialization.
  ///
  /// Older reports will be discarded when [newKey] will be applied.
  ///
  /// Invoking this method has no effect unless the agent was already
  /// initialized by calling one of the start methods.
  ///
  /// Method throws [Exception] if provided an invalid [newKey].
  ///
  /// ```dart
  /// try {
  ///   await Instrumentation.changeAppKey("AA-BBB-CCC");
  /// } catch (e) {
  ///   // handle exception
  /// }
  /// ```
  static Future<void> changeAppKey(String newKey) async {
    try {
      final args = {
        "newKey": newKey,
      };
      await channel.invokeMethod<void>('changeAppKey', args);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Crashes app from the native layer. Useful for testing crash reporting.
  ///
  /// Method might throw exception.
  ///
  /// ```dart
  /// try {
  ///   await Instrumentation.crashNatively();
  /// } catch (e) {
  ///   // handle exception
  /// }
  /// ```
  static Future<void> crash() async {
    try {
      await channel.invokeMethod<void>('crash');
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Calls thread sleep on the native layer. Useful for testing ANR reporting.
  ///
  /// Method might throw exception.
  ///
  /// ```dart
  /// try {
  ///   await Instrumentation.sleep(5000);
  /// } catch (e) {
  ///   // handle exception
  /// }
  /// ```
  static Future<void> sleep(Duration duration) async {
    try {
      final args = {"seconds": duration.inSeconds};
      await channel.invokeMethod<void>('sleep', args);
    } on PlatformException catch (e) {
      throw Exception(e.details);
    }
  }

  /// Intercepts Flutter-level errors and reports them to the controller.
  ///
  /// Warning: Does not report obfuscated apps crash reports (WIP).
  ///
  /// ```dart
  /// import 'package:flutter/material.dart';
  /// import 'package:appdynamics_agent/appdynamics_agent.dart';
  ///
  /// void main() {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   FlutterError.onError = Instrumentation.errorHandler;
  ///   runApp(MyApp());
  // }
  /// ```
  ///
  /// For capturing all hybrid-level errors (Flutter & non-Flutter), use
  /// PlatformDispatcher:
  ///
  /// ```dart
  /// void main() {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   FlutterError.onError = Instrumentation.errorHandler;
  ///   PlatformDispatcher.instance.onError = (error, stack) {
  ///     final details = FlutterErrorDetails(exception: error, stack: stack);
  ///     Instrumentation.errorHandler(details);
  ///     return true;
  ///   };
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> errorHandler(FlutterErrorDetails details) async {
    // Call private constructor for coverage. Doesn't have any other effect.
    // TODO: Remove when you can test private constructor some other way.
    Instrumentation._();

    final crashReport =
        CrashReport(errorDetails: details, stackTrace: details.stack);
    final arguments = {
      "crashDump": crashReport.toString(),
    };

    return await channel.invokeMethod<void>('createCrashReport', arguments);
  }
}
