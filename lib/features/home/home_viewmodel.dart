import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../data/supabase_repository.dart';

enum TrackStatus { locked, available, completed }

class HomeViewModel extends ChangeNotifier {
  final SupabaseRepository _repository;
  List<Track> _tracks = [];
  final Map<String, List<Phase>> _phasesByTrack = {};
  Set<String> _completedTrackIds = {};
  Set<String> _completedPhaseIds = {};
  bool _isLoading = true;

  HomeViewModel(this._repository) {
    _loadData();
  }

  List<Track> get tracks => _tracks;
  Map<String, List<Phase>> get phasesByTrack => _phasesByTrack;
  bool get isLoading => _isLoading;

  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tracks = await _repository.getTracks();
      _completedPhaseIds = await _repository.getCompletedPhaseIds();
      _completedTrackIds.clear(); // Clear existing completion state
      
      // Load phases for each track and check completion
      for (var track in _tracks) {
        final phases = await _repository.getPhases(track.id);
        _phasesByTrack[track.id] = phases;
        
        // Check if all phases in this track are completed
        if (phases.isNotEmpty && 
            phases.every((phase) => _completedPhaseIds.contains(phase.id))) {
          _completedTrackIds.add(track.id);
        }
      }
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('SocketException') || 
          errorMsg.contains('HandshakeException') ||
          errorMsg.contains('Connection closed')) {
        print('📡 Network connection issues while loading tracks. Will retry on refresh.');
      } else {
        print('Error loading tracks: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  TrackStatus getTrackStatus(int trackIndex) {
    if (trackIndex >= _tracks.length) return TrackStatus.locked;
    
    final track = _tracks[trackIndex];
    
    // Check if completed
    if (_completedTrackIds.contains(track.id)) {
      print('Track ${track.title} (Idx $trackIndex) is COMPLETED.');
      return TrackStatus.completed;
    }
    
    // Check if unlocked (first track or previous track completed)
    // The list is in ascending order (1, 2, 3, 4, 5)
    // Index 0 is "Quem eu sou" (Base) -> Always unlocked
    if (trackIndex == 0) {
      return TrackStatus.available;
    }
    
    // Check if the previous track (index - 1) is completed
    final previousTrack = _tracks[trackIndex - 1];
    
    final isPrevCompleted = _completedTrackIds.contains(previousTrack.id);
    // print('Check Unlock: ${track.title} (Idx $trackIndex) | Prev: ${previousTrack.title} | PrevCompleted: $isPrevCompleted');
    
    if (isPrevCompleted) {
      return TrackStatus.available;
    }
    
    return TrackStatus.locked;
  }

  bool isTrackUnlocked(int trackIndex) {
    final status = getTrackStatus(trackIndex);
    return status == TrackStatus.available || status == TrackStatus.completed;
  }

  bool isPhaseCompleted(String phaseId) {
    return _completedPhaseIds.contains(phaseId);
  }

  Future<void> refresh() async {
    await _loadData();
  }
}
