import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'results_screen.dart';
import 'services/auth_service.dart';
import 'services/profile_service.dart';
import 'widgets/account_sheet.dart';
import 'widgets/travel_sidebar.dart';

void main() {
  runApp(const TravelAIApp());
}

class TravelAIApp extends StatelessWidget {
  const TravelAIApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TravelAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Using a modern, consistent color scheme
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: const Color(0xFFF5F9FF), // Light blue background
        fontFamily: 'Roboto',
      ),
      home: const SearchScreen(),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // "Departing from home?" toggle state — see docs/supabase-schema-design.md §3.1.
  // _homeCity is only ever used for display here; the actual fallback logic lives
  // entirely on the backend, applied *after* Gemini parses the query, never before.
  bool _departingFromHome = false;
  bool _isLoggedIn = false;
  String? _homeCity;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    _animController.forward();
    _loadAccountContext();
  }

  @override
  void dispose() {
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Best-effort: fetches whether the user is signed in and, if so, their saved
  /// home city, purely to label the toggle. Failure here never blocks search.
  Future<void> _loadAccountContext() async {
    final loggedIn = await AuthService.isLoggedIn();
    String? homeCity;
    if (loggedIn) {
      try {
        final profile = await ProfileService.getProfile();
        homeCity = profile['homeCity'] as String?;
      } catch (_) {
        // Ignore — the toggle just won't show a home city until this succeeds.
      }
    }
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _homeCity = homeCity;
    });
  }

  Future<void> _openAccountSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AccountSheet(),
    );
    _loadAccountContext();
  }

  Future<void> _searchTravel() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your travel idea'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Dismiss keyboard
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isLoading = true);

    try {
      // /api/generate-plan never requires auth (optionalAuthenticate on the
      // backend), so this stays a plain POST rather than going through
      // ApiClient's refresh-and-retry — an expired/missing token here just means
      // the "departing from home" fallback silently doesn't apply.
      final accessToken = await AuthService.accessToken;
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/api/generate-plan'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: json.encode({
          'query': _controller.text,
          'departingFromHome': _departingFromHome,
        }),
      ).timeout(const Duration(seconds: 30)); // Added a timeout for robustness

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // **FIXED LOGIC:** Now expects the API response (data) to be the full Map<String, dynamic>
        if (data != null && data is Map<String, dynamic>) {
          final Map<String, dynamic> travelPlan = data;
          
          setState(() => _isLoading = false);
          
          // Navigate to results screen, passing the entire structured map
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultsScreen(travelPlan: travelPlan),
            ),
          );
        } else {
           // Updated error message for the new expectation
           throw Exception('Invalid response format: Expected a JSON object with travel plan details.');
        }

      } else {
        throw Exception('Server error: Status ${response.statusCode}');
      }
    } catch (e) {
      // Catch exceptions from http request, timeout, or JSON decoding
      print('Caught Error: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection Error: Could not reach the server or invalid data.'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const TravelSidebar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.blue.shade700),
        actions: [
          IconButton(
            icon: Icon(_isLoggedIn ? Icons.account_circle : Icons.account_circle_outlined),
            tooltip: _isLoggedIn ? 'Account' : 'Sign in',
            onPressed: _openAccountSheet,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: SingleChildScrollView( // Added SingleChildScrollView for keyboard overflow safety
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo/Title
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade200.withOpacity(0.5),
                            blurRadius: 25,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'TravelAI',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue.shade900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Plan your perfect trip with AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.blue.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 60),
                    
                    // Search Container
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade100,
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        enabled: !_isLoading,
                        maxLines: null,
                        minLines: 1, // Allow text to expand vertically
                        keyboardType: TextInputType.text,
                        style: const TextStyle(fontSize: 17, color: Color(0xFF1E3A8A)),
                        decoration: InputDecoration(
                          hintText: 'e.g., "I want to visit Paris for 5 days in December"',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 18,
                          ),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _isLoading
                                ? Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.blue.shade600,
                                        ),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      Icons.search,
                                      color: Colors.blue.shade600,
                                      size: 30,
                                    ),
                                    onPressed: _searchTravel,
                                  ),
                          ),
                        ),
                        onSubmitted: (_) => _searchTravel(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // "Departing from home?" toggle — see docs/supabase-schema-design.md
                    // §3.1. The value is only sent alongside the query; the
                    // Gemini prompt itself never sees the home city.
                    if (!_isLoading) _buildDepartingFromHomeToggle(),

                    const SizedBox(height: 14),

                    // Loading indicator
                    if (_isLoading)
                      Column(
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            'Generating your travel plan...',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    
                    // Example suggestions
                    if (!_isLoading) ...[
                      const SizedBox(height: 40),
                      Text(
                        'Popular searches:',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildSuggestionChip('Weekend in Rome'),
                          _buildSuggestionChip('Beach vacation in July'),
                          _buildSuggestionChip('Tokyo for 7 days'),
                          _buildSuggestionChip('Road trip through Scotland'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepartingFromHomeToggle() {
    final hasHomeCity = _homeCity != null && _homeCity!.isNotEmpty;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_outlined, size: 18, color: Colors.blue.shade400),
            const SizedBox(width: 8),
            Text(
              'Departing from home?',
              style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Switch(
              value: _departingFromHome,
              activeColor: Colors.blue.shade600,
              onChanged: hasHomeCity
                  ? (value) => setState(() => _departingFromHome = value)
                  : (_) => _openAccountSheet(),
            ),
          ],
        ),
        if (_departingFromHome && hasHomeCity)
          Text(
            "We'll use $_homeCity as your departure city if you don't mention one.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          )
        else if (!hasHomeCity)
          GestureDetector(
            onTap: _openAccountSheet,
            child: Text(
              _isLoggedIn ? 'Set a home city to use this' : 'Sign in to use this',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade400, decoration: TextDecoration.underline),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionChip(String text) {
    return GestureDetector(
      onTap: () {
        _controller.text = text;
        _searchTravel();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.blue.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100.withOpacity(0.3),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.blue.shade800,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
