import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageService.aiImagePath', () {
    test('returns "userId/ai/uuid.jpg" format', () {
      final path = StorageService.aiImagePath('user-123', 'abcd-uuid');
      expect(path, 'user-123/ai/abcd-uuid.jpg');
    });

    test('separates ai/ prefix from regular message photo path', () {
      final path = StorageService.aiImagePath('user-123', 'xyz');
      expect(path.contains('/ai/'), isTrue);
      expect(path.startsWith('user-123/'), isTrue);
    });
  });
}
