import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'common/error_codes.dart';
import 'common/error_messages.dart';
import 'models/calendar.dart';
import 'models/event.dart';
import 'models/result.dart';
import 'models/retrieve_events_params.dart';

/// Provides functionality for working with device calendar(s)
class DeviceCalendarPlugin {
  static const MethodChannel channel =
      MethodChannel('plugins.builttoroam.com/device_calendar');

  static final DeviceCalendarPlugin _instance = DeviceCalendarPlugin.private();

  factory DeviceCalendarPlugin() {
    return _instance;
  }

  @visibleForTesting
  DeviceCalendarPlugin.private();

  /// Requests permissions to modify the calendars on the device
  ///
  /// Returns a [Result] indicating if calendar READ and WRITE permissions
  /// have (true) or have not (false) been granted
  Future<Result<bool>> requestPermissions() async {
    return _invokeChannelMethod('requestPermissions');
  }

  /// Checks if permissions for modifying the device calendars have been granted
  ///
  /// Returns a [Result] indicating if calendar READ and WRITE permissions
  /// have (true) or have not (false) been granted
  Future<Result<bool>> hasPermissions() async {
    return _invokeChannelMethod('hasPermissions');
  }

  /// Retrieves all of the device defined calendars
  ///
  /// Returns a [Result] containing a list of device [Calendar]
  Future<Result<UnmodifiableListView<Calendar>>> retrieveCalendars() async {
    return _invokeChannelMethod(
      'retrieveCalendars',
      evaluateResponse: (rawData) => UnmodifiableListView(
        json.decode(rawData).map<Calendar>(
            (decodedCalendar) => Calendar.fromJson(decodedCalendar)),
      ),
    );
  }

  /// Retrieves the events from the specified calendar
  ///
  /// The `calendarId` paramter is the id of the calendar that plugin will return events for
  /// The `retrieveEventsParams` parameter combines multiple properties that
  /// specifies conditions of the events retrieval. For instance, defining [RetrieveEventsParams.startDate]
  /// and [RetrieveEventsParams.endDate] will return events only happening in that time range
  ///
  /// Returns a [Result] containing a list [Event], that fall
  /// into the specified parameters
  Future<Result<UnmodifiableListView<Event>>> retrieveEvents(
    String calendarId,
    RetrieveEventsParams retrieveEventsParams,
  ) async {
    return _invokeChannelMethod(
      'retrieveEvents',
      assertParameters: (result) {
        _validateCalendarIdParameter(
          result,
          calendarId,
        );

        _assertParameter(
          result,
          !((retrieveEventsParams?.eventIds?.isEmpty ?? true) &&
              ((retrieveEventsParams?.startDate == null ||
                      retrieveEventsParams?.endDate == null) ||
                  (retrieveEventsParams.startDate != null &&
                      retrieveEventsParams.endDate != null &&
                      retrieveEventsParams.startDate
                          .isAfter(retrieveEventsParams.endDate)))),
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.invalidRetrieveEventsParams}',
        );
      },
      arguments: () => <String, Object>{
        'calendarId': calendarId,
        'startDate': retrieveEventsParams.startDate?.millisecondsSinceEpoch,
        'endDate': retrieveEventsParams.endDate?.millisecondsSinceEpoch,
        'eventIds': retrieveEventsParams.eventIds,
      },
      evaluateResponse: (rawData) => UnmodifiableListView(json
          .decode(rawData)
          .map<Event>((decodedEvent) => Event.fromJson(decodedEvent))),
    );
  }

  /// Deletes an event from a calendar. For a recurring event, this will delete all instances of it.\
  /// To delete individual instance of a recurring event, please use [deleteEventInstance()]
  ///
  /// The `calendarId` parameter is the id of the calendar that plugin will try to delete the event from\
  /// The `eventId` parameter is the id of the event that plugin will try to delete
  ///
  /// Returns a [Result] indicating if the event has (true) or has not (false) been deleted from the calendar
  Future<Result<bool>> deleteEvent(
    String calendarId,
    String eventId,
  ) async {
    return _invokeChannelMethod(
      'deleteEvent',
      assertParameters: (result) {
        _validateCalendarIdParameter(
          result,
          calendarId,
        );

        _assertParameter(
          result,
          eventId?.isNotEmpty ?? false,
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.deleteEventInvalidArgumentsMessage}',
        );
      },
      arguments: () => <String, Object>{
        'calendarId': calendarId,
        'eventId': eventId,
      },
    );
  }

  /// Deletes an instance of a recurring event from a calendar. This should be used for a recurring event only.\
  /// If `startDate`, `endDate` or `deleteFollowingInstances` is not valid or null, then all instances of the event will be deleted.
  ///
  /// The `calendarId` parameter is the id of the calendar that plugin will try to delete the event from\
  /// The `eventId` parameter is the id of the event that plugin will try to delete\
  /// The `startDate` parameter is the start date of the instance to delete\
  /// The `endDate` parameter is the end date of the instance to delete\
  /// The `deleteFollowingInstances` parameter will also delete the following instances if set to true
  ///
  /// Returns a [Result] indicating if the instance of the event has (true) or has not (false) been deleted from the calendar
  Future<Result<bool>> deleteEventInstance(
    String calendarId,
    String eventId,
    int startDate,
    int endDate,
    bool deleteFollowingInstances,
  ) async {
    return _invokeChannelMethod(
      'deleteEventInstance',
      assertParameters: (result) {
        _validateCalendarIdParameter(
          result,
          calendarId,
        );

        _assertParameter(
          result,
          eventId?.isNotEmpty ?? false,
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.deleteEventInvalidArgumentsMessage}',
        );
      },
      arguments: () => <String, Object>{
        'calendarId': calendarId,
        'eventId': eventId,
        'eventStartDate': startDate,
        'eventEndDate': endDate,
        'followingInstances': deleteFollowingInstances,
      },
    );
  }

  /// Creates or updates an event
  ///
  /// The `event` paramter specifies how event data should be saved into the calendar
  /// Always specify the [Event.calendarId], to inform the plugin in which calendar
  /// it should create or update the event.
  ///
  /// Returns a [Result] with the newly created or updated [Event.eventId]
  Future<Result<String>> createOrUpdateEvent(Event event) async {
    return _invokeChannelMethod(
      'createOrUpdateEvent',
      assertParameters: (result) {
        // Setting time to 0 for all day events
        if (event.allDay == true) {
          event.start = DateTime(
              event.start.year, event.start.month, event.start.day, 0, 0, 0);
          event.end =
              DateTime(event.end.year, event.end.month, event.end.day, 0, 0, 0);
        }

        _assertParameter(
          result,
          !(event.allDay == true && (event?.calendarId?.isEmpty ?? true) ||
              event.start == null ||
              event.end == null),
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.createOrUpdateEventInvalidArgumentsMessageAllDay}',
        );

        _assertParameter(
          result,
          !(event.allDay != true &&
              ((event?.calendarId?.isEmpty ?? true) ||
                  event.start == null ||
                  event.end == null ||
                  event.start.isAfter(event.end))),
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.createOrUpdateEventInvalidArgumentsMessage}',
        );
      },
      arguments: () => event.toJson(),
    );
  }

  /// Creates a new local calendar for the current device.
  ///
  /// The `calendarName` parameter is the name of the new calendar\
  /// The `calendarColor` parameter is the color of the calendar. If null,
  /// a default color (red) will be used\
  /// The `localAccountName` parameter is the name of the local account:
  /// - [Android] Required. If `localAccountName` parameter is null or empty, it will default to 'Device Calendar'.
  /// If the account name already exists in the device, it will add another calendar under the account,
  /// otherwise a new local account and a new calendar will be created.
  /// - [iOS] Not used. A local account will be picked up automatically, if not found, an error will be thrown.
  ///
  /// Returns a [Result] with the newly created [Calendar.id]
  Future<Result<String>> createCalendar(
    String calendarName, {
    Color calendarColor,
    String localAccountName,
  }) async {
    return _invokeChannelMethod(
      'createCalendar',
      assertParameters: (result) {
        calendarColor ??= Colors.red;

        _assertParameter(
          result,
          calendarName?.isNotEmpty == true,
          '[${ErrorCodes.invalidArguments}] ${ErrorMessages.createCalendarInvalidCalendarNameMessage}',
        );
      },
      arguments: () => <String, Object>{
        'calendarName': calendarName,
        'calendarColor': '0x${calendarColor.value.toRadixString(16)}',
        'localAccountName': localAccountName?.isEmpty ?? true
            ? 'Device Calendar'
            : localAccountName
      },
    );
  }

  Future<Result<T>> _invokeChannelMethod<T>(
    String channelMethodName, {
    Function(Result<T>) assertParameters,
    Map<String, Object> Function() arguments,
    T Function(dynamic) evaluateResponse,
  }) async {
    final result = Result<T>();

    try {
      if (assertParameters != null) {
        assertParameters(result);
        if (result.hasErrors) {
          return result;
        }
      }

      var rawData = await channel.invokeMethod(
        channelMethodName,
        arguments != null ? arguments() : null,
      );

      if (evaluateResponse != null) {
        result.data = evaluateResponse(rawData);
      } else {
        result.data = rawData;
      }
    } catch (e) {
      _parsePlatformExceptionAndUpdateResult<T>(e, result);
    }

    return result;
  }

  void _parsePlatformExceptionAndUpdateResult<T>(
      Exception exception, Result<T> result) {
    if (exception == null) {
      result.errorMessages.add(
          '[${ErrorCodes.unknown}] Device calendar plugin ran into an unknown issue');
      return;
    }

    print(exception);

    if (exception is PlatformException) {
      result.errorMessages.add(
          '[${ErrorCodes.platformSpecific}] Device calendar plugin ran into an issue. Platform specific exception [${exception.code}], with message :\"${exception.message}\", has been thrown.');
    } else {
      result.errorMessages.add(
          '[${ErrorCodes.generic}] Device calendar plugin ran into an issue, with message \"${exception.toString()}\"');
    }
  }

  void _assertParameter<T>(
      Result<T> result, bool predicate, String errorMessage) {
    if (!predicate) {
      result.errorMessages.add(errorMessage);
    }
  }

  void _validateCalendarIdParameter<T>(
    Result<T> result,
    String calendarId,
  ) {
    _assertParameter(result, calendarId?.isNotEmpty ?? false,
        '[${ErrorCodes.invalidArguments}] ${ErrorMessages.invalidMissingCalendarId}');
  }
}
