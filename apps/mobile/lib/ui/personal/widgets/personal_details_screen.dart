import 'package:flutter/material.dart';

import '../../../domain/models/personal_details.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../settings/widgets/settings_widgets.dart';
import '../view_models/personal_details_viewmodel.dart';

/// Countries offered first (as on the website); others by their ISO code.
const _countries = {
  'US': 'United States',
  'CA': 'Canada',
  'MX': 'Mexico',
  'GB': 'United Kingdom',
  'IE': 'Ireland',
  'AU': 'Australia',
  'NZ': 'New Zealand',
  'DE': 'Germany',
  'FR': 'France',
  'NL': 'Netherlands',
  'BE': 'Belgium',
  'CH': 'Switzerland',
  'AT': 'Austria',
  'IT': 'Italy',
  'ES': 'Spain',
  'PT': 'Portugal',
  'SE': 'Sweden',
  'NO': 'Norway',
  'DK': 'Denmark',
  'FI': 'Finland',
  'PL': 'Poland',
  'CZ': 'Czechia',
  'JP': 'Japan',
  'KR': 'South Korea',
  'CN': 'China',
  'TW': 'Taiwan',
  'HK': 'Hong Kong',
  'SG': 'Singapore',
  'PH': 'Philippines',
  'IN': 'India',
  'CO': 'Colombia',
  'BR': 'Brazil',
  'AR': 'Argentina',
  'CL': 'Chile',
  'ZA': 'South Africa',
  'KE': 'Kenya',
  'IL': 'Israel',
};
const _otherCountry = '';

/// Legal name, birthday, phone, gender, address and, under 18, a parent
/// or guardian. Only the player sees them; the API keeps them encrypted.
class PersonalDetailsScreen extends StatelessWidget {
  const PersonalDetailsScreen({super.key, required this.viewModel});

  final PersonalDetailsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: Text(vm.finishing ? 'Finish signing up' : 'Personal details'),
        automaticallyImplyLeading: !vm.finishing,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.load]),
        builder: (context, _) {
          if (vm.load.running) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.load.error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage(vm.load.result)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: vm.load.execute,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _PersonalForm(viewModel: vm);
        },
      ),
    );
  }
}

class _PersonalForm extends StatefulWidget {
  const _PersonalForm({required this.viewModel});

  final PersonalDetailsViewModel viewModel;

  @override
  State<_PersonalForm> createState() => _PersonalFormState();
}

class _PersonalFormState extends State<_PersonalForm> {
  final _formKey = GlobalKey<FormState>();
  late final PersonalDetailsViewModel vm = widget.viewModel;
  late final PersonalDetails? d = vm.details;

  late final _first = TextEditingController(
    text: d?.legalFirstName ?? vm.prefillName.first,
  );
  late final _last = TextEditingController(
    text: d?.legalLastName ?? vm.prefillName.last,
  );
  late final _phone = TextEditingController(text: d?.phone);
  late final _line1 = TextEditingController(text: d?.address.line1);
  late final _line2 = TextEditingController(text: d?.address.line2);
  late final _city = TextEditingController(text: d?.address.city);
  late final _region = TextEditingController(text: d?.address.region);
  late final _postal = TextEditingController(text: d?.address.postalCode);
  late final _countryCode = TextEditingController(
    text: _countries.containsKey(d?.address.country) ? '' : d?.address.country,
  );

  late DateTime? _birth = d?.birthDate ?? vm.prefillBirthDate;
  late Gender? _gender = d?.gender;
  late String _country = d == null
      ? 'US'
      : (_countries.containsKey(d!.address.country)
            ? d!.address.country
            : _otherCountry);

  List<TextEditingController> get _controllers => [
    _first,
    _last,
    _phone,
    _line1,
    _line2,
    _city,
    _region,
    _postal,
    _countryCode,
  ];

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _us => _country == 'US';

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSaved);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSaved);
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSaved() {
    final cmd = vm.save;
    if (cmd.running) return;
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    } else if (cmd.completed) {
      cmd.clearResult();
      // Finishing: the router moves on by itself.
      if (!vm.finishing) showSnackBar(context, 'Saved.');
    }
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(_today.year - 20),
      firstDate: DateTime(1900),
      lastDate: _today,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _birth = picked);
  }

  void _submit() {
    if (vm.finishing && birthDateProblem(_birth, _today) == adultOnlyMessage) {
      vm.refuseUnderAge();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    vm.save.execute(
      PersonalDetails(
        legalFirstName: _first.text,
        legalLastName: _last.text,
        birthDate: _birth!,
        phone: _phone.text,
        gender: _gender!,
        address: Address(
          line1: _line1.text,
          line2: _line2.text,
          city: _city.text,
          region: _region.text,
          postalCode: _postal.text,
          country: _country == _otherCountry ? _countryCode.text : _country,
        ),
      ),
    );
  }

  static String? Function(String?) _required(String what) =>
      (v) => (v == null || v.trim().isEmpty) ? 'Enter $what.' : null;

  Widget _text(
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
    int? maxLength,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    TextCapitalization caps = TextCapitalization.words,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: validator,
      maxLength: maxLength,
      keyboardType: keyboard,
      autofillHints: autofill,
      textCapitalization: caps,
      textInputAction: TextInputAction.next,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.of(context).muted,
        ),
      ),
    ),
  );

  /// Boxes side by side, e.g. first and last name.
  Widget _row(List<Widget> boxes) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, box) in boxes.indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: box),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final busy = vm.save.running;
    final birthProblem = _birth == null
        ? null
        : birthDateProblem(_birth, _today);
    final form = Form(
      key: _formKey,
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (vm.finishing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'A few details for club age checks and tournament '
                  'signups. Your profile shows only your name and username.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: c.accentInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Only you can see these',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                        Text(
                          'We keep them encrypted and never show them on '
                          'your profile or to teams.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _heading('Legal name'),
            _row([
              _text(
                _first,
                'First name',
                validator: _required('your legal first name'),
                maxLength: PersonalLimits.name,
                autofill: const [AutofillHints.givenName],
              ),
              _text(
                _last,
                'Last name',
                validator: _required('your legal last name'),
                maxLength: PersonalLimits.name,
                autofill: const [AutofillHints.familyName],
              ),
            ]),
            _heading('About you'),
            FormField<DateTime>(
              initialValue: _birth,
              validator: (_) => birthDateProblem(_birth, _today),
              builder: (field) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  // Saved once, then read-only (the API refuses a change).
                  onTap: vm.birthDateLocked
                      ? null
                      : () async {
                          await _pickBirthDate();
                          field.didChange(_birth);
                        },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      helperText: vm.birthDateLocked
                          ? birthDateLockedHint
                          : 'You must be $adultAge or older.',
                      helperMaxLines: 3,
                      enabled: !vm.birthDateLocked,
                      errorText: field.errorText ?? birthProblem,
                      errorMaxLines: 2,
                      suffixIcon: Icon(
                        vm.birthDateLocked
                            ? Icons.lock_outline
                            : Icons.calendar_today_outlined,
                      ),
                    ),
                    child: Text(
                      _birth == null
                          ? 'Choose'
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_birth!),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: [
                  for (final g in Gender.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (g) => setState(() => _gender = g),
                validator: (g) => g == null ? 'Choose an option.' : null,
              ),
            ),
            _heading('Contact'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: "Your account's email.",
                  enabled: false,
                  suffixIcon: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: c.muted,
                  ),
                ),
                child: Text(vm.email ?? ''),
              ),
            ),
            _text(
              _phone,
              'Phone',
              validator: (v) => phoneProblem(v ?? ''),
              maxLength: PersonalLimits.phone,
              keyboard: TextInputType.phone,
              autofill: const [AutofillHints.telephoneNumber],
            ),
            _heading('Mailing address'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _country,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Country'),
                items: [
                  for (final e in _countries.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                  const DropdownMenuItem(
                    value: _otherCountry,
                    child: Text('Other…'),
                  ),
                ],
                onChanged: (c) => setState(() => _country = c ?? 'US'),
              ),
            ),
            if (_country == _otherCountry)
              _text(
                _countryCode,
                'Country code (two letters, e.g. GH)',
                validator: (v) =>
                    RegExp(r'^[A-Za-z]{2}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a two-letter country code.',
                maxLength: 2,
                caps: TextCapitalization.characters,
              ),
            _text(
              _line1,
              'Street address',
              validator: _required('a street address'),
              maxLength: PersonalLimits.line,
              autofill: const [AutofillHints.streetAddressLine1],
            ),
            _text(
              _line2,
              'Apartment, suite, etc. (optional)',
              maxLength: PersonalLimits.line,
              autofill: const [AutofillHints.streetAddressLine2],
            ),
            _text(
              _city,
              'City',
              validator: _required('a city'),
              maxLength: PersonalLimits.city,
              autofill: const [AutofillHints.addressCity],
            ),
            _row([
              _text(
                _region,
                _us ? 'State' : 'State / province',
                validator: _required(_us ? 'a state' : 'a state or region'),
                maxLength: PersonalLimits.region,
                autofill: const [AutofillHints.addressState],
              ),
              _text(
                _postal,
                _us ? 'ZIP code' : 'Postal code',
                validator: _required(_us ? 'a ZIP code' : 'a postal code'),
                maxLength: PersonalLimits.postalCode,
                keyboard: _us ? TextInputType.number : TextInputType.text,
                autofill: const [AutofillHints.postalCode],
                caps: TextCapitalization.characters,
              ),
            ]),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Expanded(child: form),
        // Continue (or Save) stays in reach under the form.
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(vm.finishing ? 'Continue' : 'Save'),
                  ),
                  if (vm.finishing) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: c.muted),
                      onPressed: () => vm.signOut.execute(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
