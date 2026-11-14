import 'package:flutter/material.dart';

import '../../../domain/models/personal_details.dart';
import '../../core/ui/error_message.dart';
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
      appBar: AppBar(
        title: Text(vm.finishing ? 'Finish signing up' : 'Personal details'),
        automaticallyImplyLeading: !vm.finishing,
        actions: [
          if (vm.finishing)
            TextButton(
              onPressed: () => vm.signOut.execute(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.load]),
        builder: (context, _) {
          if (vm.tooYoung) return const _TooYoung();
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

class _TooYoung extends StatelessWidget {
  const _TooYoung();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        "$tooYoungMessage We didn't keep your details, and you've been "
        'signed out.',
        textAlign: TextAlign.center,
      ),
    ),
  );
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
  late final _gName = TextEditingController(text: d?.guardian?.name);
  late final _gRelationship = TextEditingController(
    text: d?.guardian?.relationship,
  );
  late final _gEmail = TextEditingController(text: d?.guardian?.email);
  late final _gPhone = TextEditingController(text: d?.guardian?.phone);

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
    _gName,
    _gRelationship,
    _gEmail,
    _gPhone,
  ];

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _minor => _birth != null && ageOn(_birth!, _today) < adultAge;
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
    if (cmd.error && !vm.tooYoung) {
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
    if (vm.finishing && birthDateProblem(_birth, _today) == tooYoungMessage) {
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
        guardian: _minor
            ? Guardian(
                name: _gName.text,
                relationship: _gRelationship.text,
                email: _gEmail.text,
                phone: _gPhone.text,
              )
            : null,
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
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = vm.save.running;
    final birthProblem = _birth == null
        ? null
        : birthDateProblem(_birth, _today);
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (vm.finishing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Like a USA Ultimate membership, Stall 10 needs a few '
                  'details about you. Your profile shows only your name and '
                  'username.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Only you can see these'),
                subtitle: Text(
                  'We keep them encrypted and never show them on your '
                  'profile or to teams.',
                ),
              ),
            ),
            _heading('Legal name'),
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
            _heading('About you'),
            FormField<DateTime>(
              initialValue: _birth,
              validator: (_) => birthDateProblem(_birth, _today),
              builder: (field) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () async {
                    await _pickBirthDate();
                    field.didChange(_birth);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      errorText: field.errorText ?? birthProblem,
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
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
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: "Your account's email.",
                  enabled: false,
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
            if (_minor) ...[
              _heading('Parent or guardian'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  "Players under $adultAge need a parent or guardian's details.",
                  style: theme.textTheme.bodySmall,
                ),
              ),
              _text(
                _gName,
                'Name',
                validator: _required("your parent or guardian's name"),
                maxLength: PersonalLimits.name,
              ),
              _text(
                _gRelationship,
                'Relationship (optional)',
                maxLength: PersonalLimits.relationship,
              ),
              _text(
                _gEmail,
                'Email',
                validator: (v) => emailProblem(v ?? ''),
                maxLength: PersonalLimits.email,
                keyboard: TextInputType.emailAddress,
                caps: TextCapitalization.none,
              ),
              _text(
                _gPhone,
                'Phone',
                validator: (v) => phoneProblem(v ?? ''),
                maxLength: PersonalLimits.phone,
                keyboard: TextInputType.phone,
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(vm.finishing ? 'Continue' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
