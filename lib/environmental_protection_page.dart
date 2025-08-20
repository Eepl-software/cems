import 'package:flutter/material.dart';

class EnvironmentalProtectionPage extends StatelessWidget {
  const EnvironmentalProtectionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Environmental Protection Measures',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeaderSection(),
            _buildProtectionCard(
              context,
              'Advanced Dust Suppression',
              'Anti-Smog Gun for Air Quality Control',
              'To effectively control airborne dust, the site is equipped with a NEXTGEN anti-smog gun. This machine, often mounted on a Swaraj 735 FE tractor, sprays a fine mist to suppress dust particles at their source.',
              'assets/a.png',
              Colors.blue.shade50,
              Icons.air,
            ),
            _buildProtectionCard(
              context,
              'Site-Wide Water Sprinkling',
              'Sustainable Water Sprinkling',
              'We conduct regular water sprinkling on site roads and work areas to manage dust. In our commitment to sustainability, we utilize treated water from our Sewage Treatment Plant (STP) for this purpose. A 20KL water tanker is also on standby as an additional measure for watering and dust control.',
              'assets/b.png',
              Colors.cyan.shade50,
              Icons.water_drop,
            ),
            _buildProtectionCard(
              context,
              'Building & Material Containment',
              'Dust Containment Structures',
              'Building Screens: Buildings under construction are wrapped with dust protection screens to prevent dust and debris from escaping the work area.\n\nMaterial Bin Protection: The plant\'s material feeding bins are protected by enclosures made of GI Sheet to contain dust during operations.',
              'assets/c.png',
              Colors.orange.shade50,
              Icons.apartment,
            ),
            _buildProtectionCard(
              context,
              'Secure Material Transportation',
              'Safe Transport Protocols',
              'As a standard dust protection measure, all trucks transporting materials on and off the site are required to have their loads securely covered with tarpaulins. This prevents spillage and minimizes dust generation during transit.',
              'assets/d.png',
              Colors.green.shade50,
              Icons.local_shipping,
            ),
            _buildProtectionCard(
              context,
              'Concrete Slurry Management',
              'Slurry Treatment & Water Recycling',
              'A dedicated concrete slurry treatment plant is operational on-site. This system processes washout from concrete equipment, separating solid materials from water. This crucial step prevents soil and water contamination while allowing for the recycling and reuse of water.',
              'assets/e.png',
              Colors.grey.shade100,
              Icons.recycling,
            ),
            _buildProtectionCard(
              context,
              'Material Feeding Bins',
              'Dust Protection at Source',
              'The plant\'s material feeding bins are protected by enclosures made of GI Sheet to contain dust during operations. This containment system prevents dust from escaping during material handling and processing.',
              'assets/f.png',
              Colors.indigo.shade50,
              Icons.inventory_2,
            ),
            _buildProtectionCard(
              context,
              'Anti-Smog Gun Operation',
              'Mobile Dust Suppression Unit',
              'NEXTGEN anti-smog gun mounted on mobile platforms actively patrols the construction site. The system creates a fine water mist that captures airborne dust particles and brings them to the ground.',
              'assets/g.png',
              Colors.orange.shade50,
              Icons.shower,
            ),
            _buildProtectionCard(
              context,
              'Dust Protection Screens',
              'Building Perimeter Control',
              'Large-scale dust protection screens installed around building perimeters. These specialized barriers prevent dust and debris from escaping the construction zone while allowing for proper ventilation.',
              'assets/h.png',
              Colors.yellow.shade50,
              Icons.shield,
            ),
            _buildProtectionCard(
              context,
              'Covered Walkways',
              'Protected Access Routes',
              'Dust protection tunnels and covered walkways ensure safe passage through construction areas. These structures contain dust while providing protected routes for workers and equipment.',
              'assets/i.png',
              Colors.purple.shade50,
              Icons.account_tree,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.eco,
            size: 60,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          const Text(
            'Our Commitment to Environmental Protection',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'We are committed to minimizing our environmental impact through a comprehensive set of dust control and resource management initiatives on site.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionCard(
    BuildContext context,
    String category,
    String title,
    String description,
    String imagePath,
    Color backgroundColor,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.white, backgroundColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey.shade300,
                                  Colors.grey.shade200,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icon,
                                    size: 60,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Image Coming Soon',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            category,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}