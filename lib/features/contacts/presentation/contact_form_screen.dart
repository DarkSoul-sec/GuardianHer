import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../shared/widgets/feature_error.dart';
import '../application/contacts_providers.dart';
import '../application/contacts_state.dart';
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

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
          phoneNumber: _phoneController.text,
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
        submitting: _submitting,
        error: _error,
        submitLabel: 'Save contact',
        icon: Icons.person_add_alt_1,
        onSubmit: _submit,
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
  bool _initialized = false;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    if (_initialized) {
      _nameController.dispose();
      _phoneController.dispose();
    }
    super.dispose();
  }

  void _initFrom(TrustedContact contact) {
    if (_initialized) return;
    _initialized = true;
    _nameController = TextEditingController(text: contact.name);
    _phoneController = TextEditingController(text: contact.phoneNumber);
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
          phoneNumber: _phoneController.text,
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
        submitting: _submitting,
        error: _error,
        submitLabel: 'Save changes',
        icon: Icons.edit_outlined,
        onSubmit: _submit,
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
    required this.submitting,
    required this.error,
    required this.submitLabel,
    required this.icon,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final bool submitting;
  final String? error;
  final String submitLabel;
  final IconData icon;
  final VoidCallback onSubmit;

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
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: 'e.g. +1 555 123 4567',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (value) {
                      return PhoneNumber.isValid(value ?? '')
                          ? null
                          : 'Enter a valid phone number (7–15 digits).';
                    },
                    onFieldSubmitted: (_) => onSubmit(),
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