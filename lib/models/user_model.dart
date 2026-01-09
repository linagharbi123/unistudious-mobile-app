import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class UserModel extends ChangeNotifier {
  String _name = '';
  String _username = '';
  String _email = '';
  String _imageUrl = '';
  String _facebookToken = '';
  String _facebookUserId = '';
  bool _hasActiveSession = false;
  String _aboutMe = '';
  String _birthDate = ''; // Added
  String _birthPlace = ''; // Added
  String _gender = ''; // Added
  String _address = ''; // Added

  // Getters
  String get name => _name;
  String get username => _username;
  String get email => _email;
  String get imageUrl => _imageUrl;
  String get facebookToken => _facebookToken;
  String get facebookUserId => _facebookUserId;
  bool get hasActiveSession => _hasActiveSession;
  String get aboutMe => _aboutMe;
  String get birthDate => _birthDate; // Added
  String get birthPlace => _birthPlace; // Added
  String get gender => _gender; // Added
  String get address => _address; // Added

  // Setters with validation and logging
  set name(String value) {
    if (value.isEmpty) {
      if (kDebugMode) {
        developer.log('UserModel: Attempted to set empty name, ignoring', time: DateTime.now());
      }
      return;
    }
    _name = value;
    if (kDebugMode) {
      developer.log('UserModel: Name updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set username(String value) {
    if (value.isEmpty) {
      if (kDebugMode) {
        developer.log('UserModel: Attempted to set empty username, ignoring', time: DateTime.now());
      }
      return;
    }
    _username = value;
    if (kDebugMode) {
      developer.log('UserModel: Username updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set email(String value) {
    if (!value.contains('@')) {
      if (kDebugMode) {
        developer.log('UserModel: Attempted to set invalid email: $value, ignoring', time: DateTime.now());
      }
      return;
    }
    _email = value;
    if (kDebugMode) {
      developer.log('UserModel: Email updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set imageUrl(String value) {
    _imageUrl = value;
    if (kDebugMode) {
      developer.log('UserModel: Image URL updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set facebookToken(String value) {
    _facebookToken = value;
    if (kDebugMode) {
      developer.log('UserModel: Facebook token updated', time: DateTime.now());
    }
    notifyListeners();
  }

  set facebookUserId(String value) {
    _facebookUserId = value;
    if (kDebugMode) {
      developer.log('UserModel: Facebook user ID updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set hasActiveSession(bool value) {
    _hasActiveSession = value;
    if (kDebugMode) {
      developer.log('UserModel: Has active session updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set aboutMe(String value) {
    if (value.length > 500) {
      if (kDebugMode) {
        developer.log('UserModel: Attempted to set aboutMe exceeding 500 characters, ignoring', time: DateTime.now());
      }
      return;
    }
    _aboutMe = value;
    if (kDebugMode) {
      developer.log('UserModel: AboutMe updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set birthDate(String value) {
    _birthDate = value; // No strict validation here, as ProfilePage handles it
    if (kDebugMode) {
      developer.log('UserModel: BirthDate updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set birthPlace(String value) {
    _birthPlace = value;
    if (kDebugMode) {
      developer.log('UserModel: BirthPlace updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set gender(String value) {
    _gender = value;
    if (kDebugMode) {
      developer.log('UserModel: Gender updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  set address(String value) {
    _address = value;
    if (kDebugMode) {
      developer.log('UserModel: Address updated to: $value', time: DateTime.now());
    }
    notifyListeners();
  }

  // Constructor
  UserModel({
    String name = '',
    String username = '',
    String email = '',
    String imageUrl = '',
    String facebookToken = '',
    String facebookUserId = '',
    bool hasActiveSession = false,
    String aboutMe = '',
    String birthDate = '', // Added
    String birthPlace = '', // Added
    String gender = '', // Added
    String address = '', // Added
  }) {
    if (name.isNotEmpty) _name = name;
    if (username.isNotEmpty) _username = username;
    if (email.contains('@')) _email = email;
    _imageUrl = imageUrl;
    _facebookToken = facebookToken;
    _facebookUserId = facebookUserId;
    _hasActiveSession = hasActiveSession;
    if (aboutMe.length <= 500) _aboutMe = aboutMe;
    _birthDate = birthDate; // Added
    _birthPlace = birthPlace; // Added
    _gender = gender; // Added
    _address = address; // Added
    if (kDebugMode) {
      developer.log(
        'UserModel: Initialized with name: $_name, username: $_username, email: $_email, '
            'aboutMe: $_aboutMe, birthDate: $_birthDate, birthPlace: $_birthPlace, '
            'gender: $_gender, address: $_address',
        time: DateTime.now(),
      );
    }
  }

  // Method to update multiple properties
  void updateUser({
    String? name,
    String? username,
    String? email,
    String? imageUrl,
    String? facebookToken,
    String? facebookUserId,
    bool? hasActiveSession,
    String? aboutMe,
    String? birthDate, // Added
    String? birthPlace, // Added
    String? gender, // Added
    String? address, // Added
  }) {
    if (name != null && name.isNotEmpty) {
      _name = name;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set name to: $name', time: DateTime.now());
      }
    }
    if (username != null && username.isNotEmpty) {
      _username = username;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set username to: $username', time: DateTime.now());
      }
    }
    if (email != null && email.contains('@')) {
      _email = email;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set email to: $email', time: DateTime.now());
      }
    }
    if (imageUrl != null) {
      _imageUrl = imageUrl;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set imageUrl to: $imageUrl', time: DateTime.now());
      }
    }
    if (facebookToken != null) {
      _facebookToken = facebookToken;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set facebookToken', time: DateTime.now());
      }
    }
    if (facebookUserId != null) {
      _facebookUserId = facebookUserId;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set facebookUserId to: $facebookUserId', time: DateTime.now());
      }
    }
    if (hasActiveSession != null) {
      _hasActiveSession = hasActiveSession;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set hasActiveSession to: $hasActiveSession', time: DateTime.now());
      }
    }
    if (aboutMe != null && aboutMe.length <= 500) {
      _aboutMe = aboutMe;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set aboutMe to: $aboutMe', time: DateTime.now());
      }
    }
    if (birthDate != null) {
      _birthDate = birthDate;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set birthDate to: $birthDate', time: DateTime.now());
      }
    }
    if (birthPlace != null) {
      _birthPlace = birthPlace;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set birthPlace to: $birthPlace', time: DateTime.now());
      }
    }
    if (gender != null) {
      _gender = gender;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set gender to: $gender', time: DateTime.now());
      }
    }
    if (address != null) {
      _address = address;
      if (kDebugMode) {
        developer.log('UserModel: updateUser set address to: $address', time: DateTime.now());
      }
    }
    notifyListeners();
  }
}