import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/dados_remotos.dart';
import 'core/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/models/usuario.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/mapa/permissao_mapas_service.dart';
import 'features/relatorio/turno_noturno.dart';
import 'features/registro/presentation/pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sem Supabase o app segue offline; só a sincronização para.
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  } catch (e) {
    debugPrint('Supabase indisponível: $e');
  }

  // Pasta dos dados baixados; se falhar, vale o que vem no APK.
  try {
    await inicializarDadosRemotos();
  } catch (e) {
    debugPrint('Dados remotos indisponíveis: $e');
  }

  // Grupos de mapa guardados no aparelho (o servidor é lido depois).
  await PermissaoMapasService.instancia.carregarDoAparelho();
  await TurnoNoturnoService.instancia.carregarDoAparelho();


  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Erro ao obter câmeras: $e');
  }

  // Sessão salva abre direto na Home.
  Usuario? usuarioInicial;
  try {
    usuarioInicial = await AuthService.instancia.restaurarSessao();
  } catch (e) {
    debugPrint('Erro ao restaurar sessão: $e');
  }

  runApp(MyApp(cameras: cameras, usuarioInicial: usuarioInicial));
}

class MyApp extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Usuario? usuarioInicial;

  const MyApp({super.key, required this.cameras, this.usuarioInicial});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Usuario? _usuarioLogado = widget.usuarioInicial;

  void _sair() {
    AuthService.instancia.logout();
    setState(() => _usuarioLogado = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RDO cbm',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: _usuarioLogado == null
          ? LoginPage(aoLogar: (usuario) => setState(() => _usuarioLogado = usuario))
          : HomePage(
              cameras: widget.cameras,
              usuario: _usuarioLogado!,
              aoSair: _sair,
            ),
    );
  }
}
