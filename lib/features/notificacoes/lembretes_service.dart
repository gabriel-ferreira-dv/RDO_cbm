import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Lembrete de registro, de segunda a sábado: notificação local, funciona offline.
class LembretesService {
  LembretesService._interno();
  static final LembretesService instancia = LembretesService._interno();

  // Horário do lembrete (16:30, antes do fim do turno).
  static const int horaLembrete = 16;
  static const int minutoLembrete = 30;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inicializado = false;

  Future<void> _inicializar() async {
    if (_inicializado) return;
    tzdata.initializeTimeZones();
    // Fuso da obra. Sem definir, o agendamento cairia em UTC (3h adiantado).
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _inicializado = true;
  }

  Future<void> agendarLembretesDiarios(String nomeUsuario) async {
    await _inicializar();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android 13+ exige permissão explícita para notificar.
    await android?.requestNotificationsPermission();

    // Cancela só os lembretes: cancelAll() apagaria as mensagens do gestor.
    for (var dia = DateTime.monday; dia <= DateTime.saturday; dia++) {
      await _plugin.cancel(100 + dia);
    }

    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        'lembrete_registro',
        'Lembretes de registro',
        channelDescription:
            'Lembrete diário para registrar as atividades da frente de serviço',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    final primeiroNome = nomeUsuario.trim().split(' ').first;
    // DateTime.monday (1) até saturday (6) — domingo (7) fica de fora.
    for (var dia = DateTime.monday; dia <= DateTime.saturday; dia++) {
      await _plugin.zonedSchedule(
        100 + dia,
        'Registro do dia',
        '$primeiroNome, não esqueça de registrar as atividades de hoje '
            'antes de encerrar o turno!',
        _proximaOcorrencia(dia),
        detalhes,
        // Inexato: dispensa a permissão de alarme exato.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Repete toda semana nesse dia/horário.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  // Notificação imediata (mensagens do gestor).
  Future<void> exibirMensagemDoGestor(
      int idMensagem, String titulo, String corpo) async {
    await _inicializar();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        'mensagens_gestor',
        'Mensagens do gestor',
        channelDescription: 'Avisos enviados pela gestão da obra',
        importance: Importance.high,
        priority: Priority.high,
        // Expande o texto completo na barra (sem cortar em uma linha).
        styleInformation: BigTextStyleInformation(corpo),
      ),
    );
    // 1000+ para nunca colidir com os ids 101–106 dos lembretes.
    await _plugin.show(1000 + idMensagem, titulo, corpo, detalhes);
  }

  // Próxima data futura que cai no [diaDaSemana] às 16:30 (fuso da obra).
  tz.TZDateTime _proximaOcorrencia(int diaDaSemana) {
    final agora = tz.TZDateTime.now(tz.local);
    var data = tz.TZDateTime(
        tz.local, agora.year, agora.month, agora.day, horaLembrete, minutoLembrete);
    while (data.weekday != diaDaSemana || data.isBefore(agora)) {
      data = data.add(const Duration(days: 1));
    }
    return data;
  }
}
