import 'database_helper.dart';
import 'models/models.dart';

class Repository {
  final DatabaseHelper _dbHelper;

  Repository(this._dbHelper);

  // User
  Future<UserProfile?> getUserProfile() => _dbHelper.getUser();

  Future<void> createUserProfile(UserProfile user) => _dbHelper.createUser(user);

  Future<void> updateUserProfile(UserProfile user) => _dbHelper.updateUser(user);

  // Tracks & Content
  Future<List<Track>> getTracks() => _dbHelper.getAllTracks();

  Future<List<Phase>> getPhases(String trackId) => _dbHelper.getPhasesForTrack(trackId);

  Future<List<Question>> getQuestions(String phaseId) => _dbHelper.getQuestionsForPhase(phaseId);

  // Progress
  Future<void> completePhase(int userId, String phaseId, int score) async {
    await _dbHelper.markPhaseCompleted(userId, phaseId, score);
    // Logic to update XP and Level could go here or in a Service/ViewModel
    // For now, let's just save the progress
    
  }
  
  Future<bool> isPhaseCompleted(int userId, String phaseId) => _dbHelper.isPhaseCompleted(userId, phaseId);

  // Seeding
  Future<void> seedData(List<Track> tracks, List<Phase> phases, List<Question> questions) async {
    for (var track in tracks) {
      await _dbHelper.insertTrack(track);
    }
    for (var phase in phases) {
      await _dbHelper.insertPhase(phase);
    }
    for (var question in questions) {
      await _dbHelper.insertQuestion(question);
    }
  }
}
