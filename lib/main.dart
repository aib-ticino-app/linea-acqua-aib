import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

void main() {
  runApp(const AibCondottaApp());
}

class AibCondottaApp extends StatelessWidget {
  const AibCondottaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIB Condotta Parco Ticino',
      theme: ThemeData(
        primaryColor: const Color(0xFF003399),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003399)),
      ),
      home: const CondottaHomePage(),
    );
  }
}

class CondottaHomePage extends StatefulWidget {
  const CondottaHomePage({super.key});

  @override
  State<CondottaHomePage> createState() => _CondottaHomePageState();
}

class _CondottaHomePageState extends State<CondottaHomePage> {
  final MapController _mapController = MapController();
  LatLng _centerMap = const LatLng(45.55, 8.70);
  bool _mappaCentrataGPS = false;
  
  final List<LatLng> _puntiPercorso = [];
  final List<LatLng> _divisoriPunti = [];
  LatLng? _userLocation;
  
  String _startDiameter = "45";
  String _endStrategy = "UNI45_VASCA";
  double _flowRate = 200.0;
  bool _datiGenerati = false;

  double _distanzaTotaleMetri = 0;
  int _dislivelloMetri = 0;
  double _pressioneTotale = 0;
  double _pdcTotale = 0;
  int _numManichetteTotali = 0;
  int _numDivisori = 0;
  int _manichetteFinali = 0;
  String _tipoDestinazioneDesc = "";
  String _diametroFinale = "45";
  String _warningHeli = "";
  List<String> _schemaNodiTesto = [];

  @override
  void initState() {
    super.initState();
    _centraSuGPS(forzaZoom: true);
  }

  Future<void> _centraSuGPS({bool forzaZoom = true}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    
    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
      _centerMap = _userLocation!;
      if (forzaZoom || !_mappaCentrataGPS) {
        _mapController.move(_userLocation!, 15.5);
        _mappaCentrataGPS = true;
      }
    });
  }

  void _aggiornaDivisori() {
    _divisoriPunti.clear();
    if (_puntiPercorso.length < 2) return;

    double distanzaAccumulata = 0;
    double prossimoTargetDivisore = 100;

    for (int i = 0; i < _puntiPercorso.length - 1; i++) {
      LatLng p1 = _puntiPercorso[i];
      LatLng p2 = _puntiPercorso[i + 1];
      double distSegmento = Geolocator.distanceBetween(
        p1.latitude, p1.longitude, p2.latitude, p2.longitude,
      );

      while (distanzaAccumulata + distSegmento >= prossimoTargetDivisore) {
        double frazione = (prossimoTargetDivisore - distanzaAccumulata) / distSegmento;
        double latDiv = p1.latitude + (p2.latitude - p1.latitude) * frazione;
        double lngDiv = p1.longitude + (p2.longitude - p1.longitude) * frazione;
        _divisoriPunti.add(LatLng(latDiv, lngDiv));
        prossimoTargetDivisore += 100;
      }
      distanzaAccumulata += distSegmento;
    }
  }

  void _calcolaProgettoLinea() {
    if (_puntiPercorso.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno 2 punti sulla mappa!')),
      );
      return;
    }

    _distanzaTotaleMetri = 0;
    for (int i = 0; i < _puntiPercorso.length - 1; i++) {
      _distanzaTotaleMetri += Geolocator.distanceBetween(
        _puntiPercorso[i].latitude, _puntiPercorso[i].longitude,
        _puntiPercorso[i+1].latitude, _puntiPercorso[i+1].longitude,
      );
    }

    _dislivelloMetri = (_distanzaTotaleMetri * 0.10).round();
    double deltaPressioneDislivello = _dislivelloMetri / 10.0;

    double C_start = (_startDiameter == "70") ? 0.1 : (_startDiameter == "45") ? 1.0 : 10.0;
    double C_end = 1.0;
    double pArrivoRichiesta = 5.0;

    _tipoDestinazioneDesc = "UNI 45 (Attacco Fuoco)";
    _diametroFinale = "45";
    _warningHeli = "";

    if (_endStrategy == "UNI45_VASCA") {
      C_end = 1.0;
      pArrivoRichiesta = 3.0;
      _tipoDestinazioneDesc = "UNI 45 (Rifornimento Vasca AIB - 3 bar)";
      _diametroFinale = "45";
      if (_flowRate < 160) {
        _warningHeli = "⚠️ ALLARME RIFORNIMENTO ELICOTTERO: Portata < 160 l/min!";
      } else {
        _warningHeli = "✔ Portata idonea al ciclo elicottero (800L / 5 min).";
      }
    } else if (_endStrategy == "UNI45_FUOCO") {
      C_end = 1.0;
      pArrivoRichiesta = 5.0;
      _tipoDestinazioneDesc = "UNI 45 (Attacco Diretto Fuoco - 5 bar)";
      _diametroFinale = "45";
    } else if (_endStrategy == "UNI25_FUOCO") {
      C_end = 10.0;
      pArrivoRichiesta = 5.0;
      _tipoDestinazioneDesc = "UNI 25 (Linea Operativa - 5 bar)";
      _diametroFinale = "25";
    } else if (_endStrategy == "UNI25AP_FUOCO") {
      C_end = 12.0;
      pArrivoRichiesta = 5.0;
      _tipoDestinazioneDesc = "UNI 25 AP (Alta Pressione - 5 bar)";
      _diametroFinale = "25AP";
    }

    double q = _flowRate / 200.0;
    double metaMetri = _distanzaTotaleMetri / 2;
    double pdc_start = C_start * (q * q) * (metaMetri / 100.0);
    double pdc_end = C_end * (q * q) * (metaMetri / 100.0);
    _pdcTotale = pdc_start + pdc_end;

    _pressioneTotale = _pdcTotale + deltaPressioneDislivello + pArrivoRichiesta;
    _numManichetteTotali = (_distanzaTotaleMetri / 25).ceil();
    _numDivisori = (_distanzaTotaleMetri / 100).floor();
    
    int manichetteIniziali = _numManichetteTotali < (_numDivisori > 0 ? 4 : _numManichetteTotali) 
        ? _numManichetteTotali 
        : (_numDivisori > 0 ? 4 : _numManichetteTotali);

    _manichetteFinali = _numManichetteTotali - (_numDivisori * 4);
    if (_manichetteFinali < 1) _manichetteFinali = 1;

    _schemaNodiTesto.clear();
    _schemaNodiTesto.add("[ 0m ] MANDATA MOTOPOMPA: Tubo spiralato d'acqua + Mandata UNI $_startDiameter: $manichetteIniziali manichette da 25m");
    
    int metriCorrenti = 100;
    for (int i = 1; i <= _numDivisori; i++) {
      _schemaNodiTesto.add("[ ${metriCorrenti}m ] [X] DIVISORE A 3 VIE: Proseguimento UNI $_startDiameter (4 manichette da 25m)");
      metriCorrenti += 100;
    }
    int puntoArrivoMetri = _distanzaTotaleMetri.round();
    _schemaNodiTesto.add("[ ${puntoArrivoMetri}m ] ARRIVO: UNI $_diametroFinale ($_manichetteFinali manichette) - $_tipoDestinazioneDesc");

    setState(() {
      _datiGenerati = true;
    });
  }

  void _resetTracciato() {
    setState(() {
      _puntiPercorso.clear();
      _divisoriPunti.clear();
      _datiGenerati = false;
      _schemaNodiTesto.clear();
    });
  }

  Future<void> _condividiWhatsApp() async {
    final message = Uri.encodeComponent(
      "*PROGETTO CONDOTTA AIB - PARCO TICINO*\n"
      "-----------------------------------\n"
      "• Sviluppo bosco: ${_distanzaTotaleMetri.toStringAsFixed(0)} m\n"
      "• Dislivello: +$_dislivelloMetri m\n"
      "• Portata: $_flowRate l/min\n"
      "• Perdite di carico: ${_pdcTotale.toStringAsFixed(2)} bar\n"
      "-----------------------------------\n"
      "• Aspirazione (Spiralato): 1 pz\n"
      "• Mandata UNI $_startDiameter: ${_numManichetteTotali - _manichetteFinali} pz\n"
      "• Divisori 3 vie (X): $_numDivisori pz\n"
      "• Tratta Finale UNI $_diametroFinale: $_manichetteFinali pz\n"
      "• *Totale Manichette: $_numManichetteTotali pz*\n"
      "-----------------------------------\n"
      "• *Pressione Totale Pompa: ${_pressioneTotale.toStringAsFixed(1)} bar*"
    );
    final url = Uri.parse("https://api.whatsapp.com/send?text=$message");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _scaricaPDF() async {
    final pdf = pw.Document();
    int manichetteMandata = _numManichetteTotali - _manichetteFinali;

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("PARCO TICINO - PROGETTO CONDOTTA AIB", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1.5),
              pw.SizedBox(height: 8),
              pw.Text("- Sviluppo totale nel bosco: ${_distanzaTotaleMetri.toStringAsFixed(0)} m", style: const pw.TextStyle(fontSize: 11)),
              pw.Text("- Dislivello: +$_dislivelloMetri m", style: const pw.TextStyle(fontSize: 11)),
              pw.Text("- Portata gestita (Q): $_flowRate l/min", style: const pw.TextStyle(fontSize: 11)),
              pw.Text("- Perdite di carico totali: ${_pdcTotale.toStringAsFixed(2)} bar", style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 4),
              pw.Text("- Pressione Richiesta alla Pompa: ${_pressioneTotale.toStringAsFixed(1)} bar", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              pw.SizedBox(height: 10),
              pw.Text("SCHEMA LINEA:", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ..._schemaNodiTesto.map((n) => pw.Text("- $n", style: const pw.TextStyle(fontSize: 9))),
              pw.SizedBox(height: 10),
              pw.Text("DISTINTA MATERIALI:", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text("- Tubo spiralato aspirazione: 1 pz", style: const pw.TextStyle(fontSize: 10)),
              pw.Text("- Tubi UNI $_startDiameter: $manichetteMandata pz", style: const pw.TextStyle(fontSize: 10)),
              pw.Text("- Divisori a 3 vie (X): $_numDivisori pz", style: const pw.TextStyle(fontSize: 10)),
              pw.Text("- Tratta Finale UNI $_diametroFinale: $_manichetteFinali pz", style: const pw.TextStyle(fontSize: 10)),
              pw.Text("- Totale Manichette Impiegate: $_numManichetteTotali pz", style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    int manichetteMandata = _numManichetteTotali - _manichetteFinali;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003399),
        elevation: 2,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Image.asset('logo.png', height: 36, errorBuilder: (c, e, s) => const Icon(Icons.shield, color: Color(0xFF003399))),
            ),
            const SizedBox(width: 12),
            const Text('PARCO TICINO - PROGETTO CONDOTTA AIB', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.my_location, color: Colors.white),
              tooltip: 'Centra sulla mia posizione GPS',
              onPressed: () => _centraSuGPS(forzaZoom: true),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          Container(
            width: 450,
            color: const Color(0xFFF4F4F4),
            padding: const EdgeInsets.all(12),
            child: ListView(
              children: [
                const Text('Parametri Progetto Linea', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(left: BorderSide(color: Color(0xFF003399), width: 4)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: const Text(
                    'Tracciamento nel Bosco: Usa il tasto 🎯 in alto a destra sulla mappa per centrarti col GPS. Clicca in sequenza (A = Motopompa, punti intermedi, B = Arrivo).',
                    style: TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 12),

                const Text('1. Diametro di Partenza (Mandata Motopompa):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                DropdownButtonFormField<String>(
                  value: _startDiameter,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: '70', child: Text('UNI 70 (C = 0.1) - Grande Portata', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: '45', child: Text('UNI 45 (C = 1.0) - Standard', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: '25', child: Text('UNI 25 (C = 10.0)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setState(() => _startDiameter = val!),
                ),
                const SizedBox(height: 10),

                const Text('2. Obiettivo / Destinazione Finale:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                DropdownButtonFormField<String>(
                  value: _endStrategy,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: 'UNI45_VASCA', child: Text('Rifornimento Vasca AIB (Elicottero Bucket 800L / 5 min)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'UNI45_FUOCO', child: Text('Attacco al Fuoco (UNI 45, 5 bar a lancia)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'UNI25_FUOCO', child: Text('Linea Operativa / Attacco (UNI 25, 5 bar a lancia)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'UNI25AP_FUOCO', child: Text('Alta Pressione (UNI 25 AP, 5 bar)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setState(() => _endStrategy = val!),
                ),
                const SizedBox(height: 10),

                const Text('3. Portata Obiettivo (Q):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                DropdownButtonFormField<double>(
                  value: _flowRate,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: 200.0, child: Text('200 l/min (Consigliato per Bucket 800L)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 160.0, child: Text('160 l/min (Minimo teorico Bucket 800L/5min)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 125.0, child: Text('125 l/min', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 100.0, child: Text('100 l/min', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setState(() => _flowRate = val!),
                ),
                const SizedBox(height: 12),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003399), foregroundColor: Colors.white),
                  onPressed: _calcolaProgettoLinea,
                  child: const Text('Genera Progetto'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700], foregroundColor: Colors.white),
                  onPressed: _resetTracciato,
                  child: const Text('Pulisci Tracciato'),
                ),
                const SizedBox(height: 10),

                if (_datiGenerati) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "PROGETTO CONDOTTA AIB (LOGICA MOTOPOMPA)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black),
                        ),
                        const Divider(thickness: 1),
                        Text(
                          "• Sviluppo bosco: ${_distanzaTotaleMetri.toStringAsFixed(0)} m | Dislivello: +$_dislivelloMetri m (+${(_dislivelloMetri/10).toStringAsFixed(1)} bar)\n"
                          "• Portata: $_flowRate l/min | Perdite carico: ${_pdcTotale.toStringAsFixed(2)} bar | Pressione Pompa: ${_pressioneTotale.toStringAsFixed(1)} bar",
                          style: const TextStyle(fontSize: 11, height: 1.3),
                        ),
                        if (_warningHeli.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_warningHeli, style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          "SCHEMA LINEA (PARTENZA DALLA MOTOPOMPA):",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        ..._schemaNodiTesto.map((nodoTesto) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 35,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF003399),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    bottomLeft: Radius.circular(4),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    nodoTesto,
                                    style: const TextStyle(fontSize: 10, height: 1.2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                        const SizedBox(height: 8),
                        Text(
                          "DISTINTA MATERIALI: Tubo spiralato aspirazione: 1 pz | Tubi UNI $_startDiameter: $manichetteMandata pz | Tubi UNI $_diametroFinale: $_manichetteFinali pz | Divisori (X): $_numDivisori pz | Totale Manichette: $_numManichetteTotali pz",
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                    onPressed: _condividiWhatsApp,
                    icon: const Icon(Icons.share),
                    label: const Text('Invia Dati Completi su WhatsApp'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    onPressed: _scaricaPDF,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Scarica Progetto in PDF'),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text("Stato: In attesa di tracciamento sulla mappa...", style: TextStyle(fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
          
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _centerMap,
                initialZoom: 15.5,
                onTap: (tapPosition, point) {
                  setState(() {
                    _puntiPercorso.add(point);
                    _aggiornaDivisori();
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.aib.condotta',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _puntiPercorso,
                      color: const Color(0xFF003399),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_userLocation != null)
                      Marker(
                        point: _userLocation!,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF003399),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black45)],
                          ),
                        ),
                      ),
                    ..._puntiPercorso.map((p) => Marker(
                          point: p,
                          width: 30,
                          height: 30,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                        )),
                    ..._divisoriPunti.map((d) => Marker(
                          point: d,
                          width: 24,
                          height: 24,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Text('X', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}