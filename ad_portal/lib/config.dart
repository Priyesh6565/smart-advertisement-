import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO: paste your values from Supabase > Project Settings > API
const supabaseUrl = 'https://irjmlvsovpecegtsmkox.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlyam1sdnNvdnBlY2VndHNta294Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyNTI2MzQsImV4cCI6MjEwNjgyODYzNH0.hzuAQkrfPyQL1P_b2ZsvSYptOiN2Q6E6b1jd8U73rmc';

SupabaseClient get supabase => Supabase.instance.client;

// DB value -> label shown in the app
const ageLabels = {
  'teens': '10-20',
  'adults': '20-49',
  'seniors': '50-80',
  'all': 'All ages',
};
const genderLabels = {
  'male': 'Male',
  'female': 'Female',
  'all': 'All genders',
};

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

String money(dynamic v) => '₹${toD(v).toStringAsFixed(2)}';

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}
