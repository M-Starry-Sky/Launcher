import 'package:flutter_test/flutter_test.dart';

import 'package:xingqiong_launcher/core/auth/microsoft_game_auth.dart';
import 'package:xingqiong_launcher/core/auth/microsoft_oauth.dart';

void main() {
  test('empty client id uses Live public client', () {
    expect(MicrosoftOAuth.resolveClientId(''), MicrosoftOAuth.livePublicClientId);
    expect(MicrosoftOAuth.resolveClientId('  '), MicrosoftOAuth.livePublicClientId);
    expect(
      MicrosoftOAuth.detectKind(MicrosoftOAuth.livePublicClientId),
      MicrosoftAuthKind.liveXbox,
    );
  });

  test('Azure GUID uses device code', () {
    const guid = '11111111-2222-3333-4444-555555555555';
    expect(MicrosoftOAuth.detectKind(guid), MicrosoftAuthKind.azureDeviceCode);
    expect(
      MicrosoftOAuth.detectKind('11111111222233334444555555555555'),
      MicrosoftAuthKind.azureDeviceCode,
    );
  });

  test('extractAuthCode from desktop redirect', () {
    const url =
        'https://login.live.com/oauth20_desktop.srf?code=M.C123%2Bxx&lc=1033';
    expect(MicrosoftOAuth.extractAuthCode(url), 'M.C123+xx');
    expect(MicrosoftOAuth.extractAuthCode('barecode'), 'barecode');
  });

  test('Xbox RpsTicket prefix', () {
    expect(MicrosoftGameAuth.rpsTicketForXbox('eyJhbGciOi'), 'd=eyJhbGciOi');
    expect(MicrosoftGameAuth.rpsTicketForXbox('t=EwAoA'), 't=EwAoA');
    expect(MicrosoftGameAuth.rpsTicketForXbox('d=abc'), 'd=abc');
    expect(MicrosoftGameAuth.rpsTicketForXbox('EwAoAnotjwt'), 'EwAoAnotjwt');
  });
}
