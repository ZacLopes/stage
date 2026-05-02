import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('career_gamification.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const idTypeInt = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';

    // User Profile
    await db.execute('''
CREATE TABLE user_profile (
  id $idTypeInt,
  name $textType,
  email $textType,
  course $textType,
  semester $textType
)
''');

    // Tracks
    await db.execute('''
CREATE TABLE tracks (
  id $idType,
  title $textType,
  description $textType,
  color $intType,
  iconAsset $textType
)
''');

    // Phases
    await db.execute('''
CREATE TABLE phases (
  id $idType,
  trackId $textType,
  orderIndex $intType,
  title $textType,
  description $textType,
  FOREIGN KEY (trackId) REFERENCES tracks (id)
)
''');

    // Questions
    await db.execute('''
CREATE TABLE questions (
  id $idType,
  phaseId $textType,
  type $intType,
  content $textType,
  options $textType,
  FOREIGN KEY (phaseId) REFERENCES phases (id)
)
''');

    // Badges
    await db.execute('''
CREATE TABLE badges (
  id $idType,
  name $textType,
  description $textType,
  iconAsset $textType,
  conditionType $textType,
  conditionValue $intType
)
''');

    // User Badges (Many-to-Many)
    await db.execute('''
CREATE TABLE user_badges (
  userId $intType,
  badgeId $textType,
  dateEarned $textType,
  PRIMARY KEY (userId, badgeId),
  FOREIGN KEY (userId) REFERENCES user_profile (id),
  FOREIGN KEY (badgeId) REFERENCES badges (id)
)
''');

    // User Progress (Track Phase Completion)
    await db.execute('''
CREATE TABLE user_progress (
  userId $intType,
  phaseId $textType,
  completed $boolType,
  PRIMARY KEY (userId, phaseId),
  FOREIGN KEY (userId) REFERENCES user_profile (id),
  FOREIGN KEY (phaseId) REFERENCES phases (id)
)
''');
  }

  // --- User Profile Operations ---
  Future<UserProfile> createUser(UserProfile user) async {
    final db = await instance.database;
    final id = await db.insert('user_profile', user.toMap());
    return user; // In a real app, we'd copyWith(id: id) but UserProfile id is optional/auto-inc
  }

  Future<UserProfile?> getUser() async {
    final db = await instance.database;
    final maps = await db.query('user_profile');

    if (maps.isNotEmpty) {
      return UserProfile.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<int> updateUser(UserProfile user) async {
    final db = await instance.database;
    return db.update(
      'user_profile',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // --- Track Operations ---
  Future<void> insertTrack(Track track) async {
    final db = await instance.database;
    await db.insert('tracks', track.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Track>> getAllTracks() async {
    final db = await instance.database;
    final result = await db.query('tracks');
    return result.map((json) => Track.fromMap(json)).toList();
  }

  // --- Phase Operations ---
  Future<void> insertPhase(Phase phase) async {
    final db = await instance.database;
    await db.insert('phases', phase.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Phase>> getPhasesForTrack(String trackId) async {
    final db = await instance.database;
    final result = await db.query(
      'phases',
      where: 'trackId = ?',
      whereArgs: [trackId],
      orderBy: 'orderIndex ASC',
    );
    return result.map((json) => Phase.fromMap(json)).toList();
  }

  // --- Question Operations ---
  Future<void> insertQuestion(Question question) async {
    final db = await instance.database;
    await db.insert('questions', question.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Question>> getQuestionsForPhase(String phaseId) async {
    final db = await instance.database;
    final result = await db.query(
      'questions',
      where: 'phaseId = ?',
      whereArgs: [phaseId],
    );
    return result.map((json) => Question.fromMap(json)).toList();
  }
  
  // --- Progress Operations ---
  Future<void> markPhaseCompleted(int userId, String phaseId) async {
    final db = await instance.database;
    await db.insert('user_progress', {
      'userId': userId,
      'phaseId': phaseId,
      'completed': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<bool> isPhaseCompleted(int userId, String phaseId) async {
    final db = await instance.database;
    final result = await db.query(
      'user_progress',
      where: 'userId = ? AND phaseId = ? AND completed = 1',
      whereArgs: [userId, phaseId],
    );
    return result.isNotEmpty;
  }

  Future<void> clearAllUserData() async {
    final db = await instance.database;
    await db.delete('user_profile');
    await db.delete('user_badges');
    await db.delete('user_progress');
    print('🧹 Local SQLite data cleared.');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
