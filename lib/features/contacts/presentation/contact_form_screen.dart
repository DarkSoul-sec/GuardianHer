import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../shared/widgets/feature_error.dart';
import '../application/contacts_providers.dart';
import '../application/contacts_state.dart';
import '../domain/country_code.dart';
import '../domain/phone_number.dart';
import '../domain/trusted_contact.dart';
import '../domain/trusted_contact_validator.dart';

/// Creates a new trusted contact.
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String _countryCode = CountryCode.defaultDialing;
  bool _submitting = false;
  String? _error;
  bool _isEmergencyContact = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(contactsControllerProvider.notifier)
        .addContact(
          name: _nameController.text,
          phoneNumber:
              PhoneNumber.withDialingCode(_countryCode, _phoneController.text),
          email: _emailController.text,
          isEmergencyContact: _isEmergencyContact,
        );

    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact added')),
        );
      case Err(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add contact')),
      body: _ContactFormFields(
        formKey: _formKey,
        nameController: _nameController,
        phoneController: _phoneController,
        emailController: _emailController,
        countryCode: _countryCode,
        onCountryCodeChanged: (code) => setState(() => _countryCode = code),
        submitting: _submitting,
        error: _error,
        submitLabel: 'Save contact',
        icon: Icons.person_add_alt_1,
        onSubmit: _submit,
        initialIsEmergencyContact: _isEmergencyContact,
        onEmergencyContactChanged: (value) => setState(() => _isEmergencyContact = value),
      ),
    );
  }
}

/// Edits an existing trusted contact.
///
/// Reached with a contact [id]; the form is populated from the loaded contact
/// list. Editing shows the stored full phone number because the user is
/// explicitly modifying their own contact.
class EditContactScreen extends ConsumerStatefulWidget {
  const EditContactScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends ConsumerState<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  bool _initialized = false;
  bool _isEmergencyContact = true;

  String _countryCode = CountryCode.defaultDialing;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    if (_initialized) {
      _nameController.dispose();
      _phoneController.dispose();
      _emailController.dispose();
    }
    super.dispose();
  }

  void _initFrom(TrustedContact contact) {
    if (_initialized) return;
    _initialized = true;
    _nameController = TextEditingController(text: contact.name);
    _isEmergencyContact = contact.isEmergencyContact;
    // Show only the national number when a known country prefix is stored,
    // defaulting to +91; otherwise show the stored number as-is.
    final matched = CountryCode.common
        .where((code) =>
            contact.phoneNumber.startsWith(PhoneNumber.normalize(code.dialing)) &&
            contact.phoneNumber.length > PhoneNumber.normalize(code.dialing).length)
        .firstOrNull;
    _countryCode = matched?.dialing ?? CountryCode.defaultDialing;
    _phoneController = TextEditingController(
      text: PhoneNumber.stripDialingCode(_countryCode, contact.phoneNumber),
    );
    _emailController = TextEditingController(text: contact.email ?? '');
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(contactsControllerProvider.notifier)
        .updateContact(
          id: widget.id,
          name: _nameController.text,
          phoneNumber:
              PhoneNumber.withDialingCode(_countryCode, _phoneController.text),
          email: _emailController.text,
          isEmergencyContact: _isEmergencyContact,
        );

    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact updated')),
        );
      case Err(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactsControllerProvider);
    final contact = switch (state) {
      ContactsLoaded(:final contacts) =>
        contacts.where((c) => c.id == widget.id).firstOrNull,
      _ => null,
    };

    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit contact')),
        body: state is ContactsLoading
            ? const Center(child: CircularProgressIndicator())
            : const FeatureError(message: 'This contact no longer exists.'),
      );
    }

    _initFrom(contact);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit contact')),
      body: _ContactFormFields(
        formKey: _formKey,
        nameController: _nameController,
        phoneController: _phoneController,
        emailController: _emailController,
        countryCode: _countryCode,
        onCountryCodeChanged: (code) => setState(() => _countryCode = code),
        submitting: _submitting,
        error: _error,
        submitLabel: 'Save changes',
        icon: Icons.edit_outlined,
        onSubmit: _submit,
        initialIsEmergencyContact: _isEmergencyContact,
        onEmergencyContactChanged: (value) => setState(() => _isEmergencyContact = value),
      ),
    );
  }
}

/// Shared add/edit form with validation, error display and a submit action.
class _ContactFormFields extends StatelessWidget {
  const _ContactFormFields({
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.countryCode,
    required this.onCountryCodeChanged,
    required this.submitting,
    required this.error,
    required this.submitLabel,
    required this.icon,
    required this.onSubmit,
    this.initialIsEmergencyContact = true,
    this.onEmergencyContactChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final String countryCode;
  final ValueChanged<String> onCountryCodeChanged;
  final bool submitting;
  final String? error;
  final String submitLabel;
  final IconData icon;
  final VoidCallback onSubmit;
  final bool initialIsEmergencyContact;
  final ValueChanged<bool>? onEmergencyContactChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return 'Enter a name.';
                      if (trimmed.length > TrustedContactValidator.maxNameLength) {
                        return 'Name must be '
                            '${TrustedContactValidator.maxNameLength} characters '
                            'or fewer.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Phone number',
                      hintText: 'e.g. 8965421745',
                      border: const OutlineInputBorder(),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 96,
                        maxWidth: 96,
                      ),
                      prefixIcon: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: countryCode,
                          isDense: true,
                          isExpanded: false,
                          style: theme.textTheme.bodySmall,
                          borderRadius: BorderRadius.circular(8),
                          items: [
                            for (final code in CountryCode.common)
                              DropdownMenuItem(
                                value: code.dialing,
                                child: Text(code.dialing),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              onCountryCodeChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                    validator: (value) {
                      final full = PhoneNumber.withDialingCode(
                        countryCode,
                        value ?? '',
                      );
                      return PhoneNumber.isValid(full)
                          ? null
                          : 'Enter a valid phone number (7–15 digits).';
                    },
                    onFieldSubmitted: (_) => onSubmit(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      hintText: 'Used if no SMS app is available',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (value) {
                      final normalized = TrustedContact.normalizeEmail(value);
                      if (normalized != null &&
                          !TrustedContactValidator.isValidEmail(normalized)) {
                        return 'Enter a valid email address or leave it empty.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => onSubmit(),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Receive SOS alerts'),
                    subtitle: const Text(
                      'Include this contact in emergency SOS messages',
                    ),
                    value: initialIsEmergencyContact,
                    onChanged: onEmergencyContactChanged,
                    secondary: const Icon(Icons.warning_amber_rounded),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: submitting ? null : onSubmit,
                    child: submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(submitLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}