import 'package:flutter/material.dart';

class ResultsScreen extends StatefulWidget {
  final Map<String, dynamic> travelPlan;

  const ResultsScreen({Key? key, required this.travelPlan}) : super(key: key);

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  // --- SAFE DATA ACCESSORS (Helper Getters for nested backend data) ---

  // Get the core AI-extracted plan details
  Map<String, dynamic> get _planSummary => 
      widget.travelPlan['planSummary'] as Map<String, dynamic>? ?? {};
  
  // Get individual data points from planSummary
  String get _destinationCity => _planSummary['destinationCity'] ?? 'Unknown City';
  String get _departureCity => _planSummary['departureCity'] ?? 'Not specified';
  String get _startDate => _planSummary['startDate'] ?? 'flexible';
  String get _endDate => _planSummary['endDate'] ?? 'flexible';
  String get _duration => _planSummary['duration'] ?? 'N/A';
  String get _travelers => _planSummary['travelers'] ?? '1';
  String get _budget => (_planSummary['budget'] ?? 'medium').toString().toLowerCase();

  // Get external API data sets
  Map<String, dynamic> get _flightData => widget.travelPlan['flights'] as Map<String, dynamic>? ?? {'data': []};
  Map<String, dynamic> get _hotelData => widget.travelPlan['hotels'] as Map<String, dynamic>? ?? {'data': []};
  Map<String, dynamic> get _weatherData => widget.travelPlan['weather'] as Map<String, dynamic>? ?? {'forecast': []};
  Map<String, dynamic> get _newsData => widget.travelPlan['news'] as Map<String, dynamic>? ?? {'articles': []};
  Map<String, dynamic> get _visaData => widget.travelPlan['visa'] as Map<String, dynamic>? ?? {'requirement': 'Unknown'};

  // --- WIDGET LOGIC ---

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.blue.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Your Travel Plan',
          style: TextStyle(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _animation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Destination Header
              _buildDestinationHeader(),
              const SizedBox(height: 20),

              // Flight Card
              _buildFlightCard(),
              const SizedBox(height: 16),

              // Hotel Card
              _buildHotelCard(),
              const SizedBox(height: 16),

              // Weather Card (Now dynamic)
              _buildWeatherCard(),
              const SizedBox(height: 16),

              // Visa Card (Now dynamic)
              _buildVisaCard(),
              const SizedBox(height: 16),

              // News Card (Now dynamic)
              _buildNewsCard(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              Expanded(
                // Use destinationCity from planSummary
                child: Text(
                  _destinationCity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Use duration and travelers from planSummary
          Text(
            '$_duration • $_travelers traveler(s)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildFlightCard() {
  final List<dynamic> flights = _flightData['data'] ?? [];
  
  final Map<String, dynamic>? firstFlight = flights.isNotEmpty ? flights.first : null;
  
  // FIX: Properly handle price as number
  final String flightPrice = firstFlight != null 
    ? '\$${(firstFlight['price'] as num).toStringAsFixed(0)} ${firstFlight['currency']}' 
    : '\$${_estimateFlightPrice()} (Est.)';

  final String statusMessage = firstFlight != null
    ? 'Actual price found'
    : _flightData['message']?.toString() ?? 'No current flight data found.';

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.shade100,
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.flight_takeoff, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(
                'Flight Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Departure',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _departureCity,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(_startDate),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Icon(Icons.arrow_forward,
                          color: Colors.blue.shade300, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        _duration,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Arrival',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _destinationCity,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(_startDate),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Price',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    flightPrice,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                statusMessage,
                style: TextStyle(
                  color: firstFlight != null ? Colors.green.shade600 : Colors.orange.shade600,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildHotelCard() {
  final List<dynamic> hotels = _hotelData['data'] ?? [];
  
  final Map<String, dynamic>? firstHotel = hotels.isNotEmpty ? hotels.first : null;
  
  // FIX: Properly handle REAL price as number
  final String hotelPrice = firstHotel != null 
    ? '\$${(firstHotel['pricePerNight'] as num).toStringAsFixed(0)}' 
    : '\$${_estimateHotelPrice()} (Est.)';
  
  final String totalPrice = firstHotel != null
    ? '\$${(firstHotel['totalPrice'] as num).toStringAsFixed(0)}'
    : 'N/A';

  final String statusMessage = firstHotel != null
    ? 'Real prices from Amadeus'
    : _hotelData['message']?.toString() ?? 'No current hotel data found.';

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.shade100,
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.hotel, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(
                'Accommodation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hotel Name',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          firstHotel?['name'] ?? 'Recommended Hotel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rating',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        firstHotel?['rating']?.toString() ?? _budget.toUpperCase(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Check-in: ${_formatDate(_startDate)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Check-out: ${_formatDate(_endDate)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Price per night',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    hotelPrice,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
              if (firstHotel != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total stay',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      totalPrice,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade500,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                statusMessage,
                style: TextStyle(
                  color: firstHotel != null ? Colors.green.shade600 : Colors.orange.shade600,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildWeatherCard() {
    final List<dynamic> forecast = _weatherData['forecast'] ?? [];

    // Use up to 4 days of the actual forecast if available
    final List<Map<String, dynamic>> displayedForecast = forecast.take(4).map((day) => day as Map<String, dynamic>).toList();

    // If no real forecast, use static placeholders
    if (displayedForecast.isEmpty) {
       return Container(
         padding: const EdgeInsets.all(20),
         decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(16),
           boxShadow: [
             BoxShadow(
               color: Colors.blue.shade100,
               blurRadius: 10,
               offset: const Offset(0, 3),
             ),
           ],
         ),
         child: Text(
           _weatherData['message']?.toString() ?? 'Weather data not available for the requested period.',
           style: TextStyle(color: Colors.red.shade600),
         ),
       );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.wb_sunny, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text(
                  'Weather Forecast (${_weatherData['location'] ?? 'Destination'})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: displayedForecast.map((day) {
                final date = DateTime.tryParse(day['date'].toString());
                final dayName = date != null ? _getDayName(date.weekday) : 'Day';
                final temp = '${day['maxTempC']?.toStringAsFixed(0) ?? 'N/A'}°C';
                final condition = day['condition']?.toString().toLowerCase() ?? 'sunny';
                final icon = _getWeatherIcon(condition);
                
                return _buildWeatherDay(dayName, temp, icon);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDay(String day, String temp, IconData icon) {
    return Column(
      children: [
        Text(
          day,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Icon(icon, color: Colors.orange.shade400, size: 32),
        const SizedBox(height: 8),
        Text(
          temp,
          style: TextStyle(
            color: Colors.blue.shade700,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildVisaCard() {
    // Determine requirement based on the text returned by the mock API (e.g., 'Visa Required')
    final String requirement = _visaData['requirement']?.toString() ?? 'Unknown';
    final bool needsVisa = requirement.toLowerCase().contains('visa required');

    final String title = needsVisa ? 'Visa MAY be Required' : 'No Visa Required';
    final String description = needsVisa 
        ? 'Please check official sources. Requirement: $requirement.'
        : 'Requirement: $requirement.';
    
    final Color iconColor = needsVisa ? Colors.orange.shade600 : Colors.green.shade600;
    final Color bgColor = needsVisa ? Colors.orange.shade50 : Colors.green.shade50;
    final IconData icon = needsVisa ? Icons.info_outline : Icons.check_circle_outline;


    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard() {
    final List<dynamic> newsItems = _newsData['articles'] ?? [];
    
    // If no real news, display the message from the API call
    if (newsItems.isEmpty) {
       return Container(
         padding: const EdgeInsets.all(20),
         decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(16),
           boxShadow: [
             BoxShadow(
               color: Colors.blue.shade100,
               blurRadius: 10,
               offset: const Offset(0, 3),
             ),
           ],
         ),
         child: Text(
           _newsData['message']?.toString() ?? 'No recent news found for ${_destinationCity}.',
           style: TextStyle(color: Colors.red.shade600),
         ),
       );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.article, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text(
                  'Latest News about $_destinationCity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: newsItems.length,
            separatorBuilder: (context, index) =>
                Divider(color: Colors.grey.shade200, height: 1),
            itemBuilder: (context, index) {
              final news = newsItems[index] as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      news['title']?.toString() ?? 'News Title Missing',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      news['source']?.toString() ?? 'Unknown Source',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  // --- UTILITY METHODS ---

  String _formatDate(dynamic date) {
    if (date == null || date == 'flexible') return 'Flexible Date';
    try {
      final dateStr = date.toString();
      // Simple YYYY-MM-DD parsing (like from AI output)
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        final months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${months[int.parse(parts[1]) - 1]} ${parts[2]}, ${parts[0]}';
      }
      return dateStr;
    } catch (e) {
      return date.toString();
    }
  }

  String _estimateFlightPrice() {
    switch (_budget) {
      case 'low': return '250';
      case 'medium': return '450';
      case 'high': return '800';
      case 'luxury': return '1500';
      default: return '450';
    }
  }

  String _estimateHotelPrice() {
    switch (_budget) {
      case 'low': return '60';
      case 'medium': return '120';
      case 'high': return '250';
      case 'luxury': return '500';
      default: return '120';
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Mon';
      case 2: return 'Tue';
      case 3: return 'Wed';
      case 4: return 'Thu';
      case 5: return 'Fri';
      case 6: return 'Sat';
      case 7: return 'Sun';
      default: return '';
    }
  }

  IconData _getWeatherIcon(String condition) {
    if (condition.contains('rain') || condition.contains('drizzle')) return Icons.beach_access;
    if (condition.contains('cloud') || condition.contains('overcast')) return Icons.cloud;
    if (condition.contains('sun') || condition.contains('clear')) return Icons.wb_sunny;
    if (condition.contains('snow') || condition.contains('sleet')) return Icons.ac_unit;
    if (condition.contains('thunder')) return Icons.flash_on;
    return Icons.wb_sunny;
  }
}
