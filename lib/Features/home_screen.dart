import 'package:flutter/material.dart';
import 'package:ultimatefrisbeeapp/Features/desktop_home.dart';
import 'package:ultimatefrisbeeapp/Features/mobile_home.dart';
import 'package:ultimatefrisbeeapp/Features/tablet_home.dart';

class HomeScreenWrapper extends StatefulWidget {
  const HomeScreenWrapper({super.key});

  @override
  State<HomeScreenWrapper> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreenWrapper> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth > 1200){
        return DesktopHomeScreen();
      }
      if (constraints.maxWidth < 1200 && constraints.maxWidth > 600){
        return TabletHomeScreen();
      }
     
        return MobileHomeScreen();
      
    });
  }
}