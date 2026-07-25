import 'package:flutter/material.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return  Scaffold(appBar: AppBar(title: const Text("Desktop Home"),), body:Container(color:Colors.purple));}
}