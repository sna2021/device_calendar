class Result<T> {
  /// Indicates if the request was successfull or not
  ///
  /// Returns true if data is not null and there're no error messages, otherwise returns false
  bool get isSuccess {
    var res = data != null && errorMessages.isEmpty;
    if (res) {
      if (data is String) {
        res = (data as String).isNotEmpty;
      }
    }

    return res;
  }

  /// Indicates if there are errors. This isn't exactly the same as !isSuccess since
  /// it doesn't look at the state of the data.
  ///
  /// Returns true if there are error messages, otherwise false
  bool get hasErrors {
    return errorMessages.isNotEmpty;
  }

  T data;
  List<String> errorMessages = <String>[];
}
