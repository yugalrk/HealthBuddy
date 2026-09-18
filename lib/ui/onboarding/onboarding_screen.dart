/// First-run flow: background, goal, household, diet, preferences.
library;

import 'package:flutter/material.dart';

import '../../models/food.dart';
import '../../models/profile.dart';
import '../widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.ingredients,
    required this.onComplete,
    this.initial,
  });

  final Map<String, Ingredient> ingredients;
  final ValueChanged<Profile> onComplete;

  /// When editing an existing profile rather than onboarding.
  final Profile? initial;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Primary person
  late int _age;
  late Sex _sex;
  late double _heightCm;
  late double _weightKg;
  late ActivityLevel _activity;
  late Goal _goal;

  late DietType _diet;
  late List<HouseholdMember> _others;
  late Set<String> _liked;
  late Set<String> _disliked;
  late Set<String> _allergens;
  late bool _includeSnacks;
  late List<DayRule> _dayRules;
  late ShoppingRhythm _shopping;
  String _prefQuery = '';

  int get _pageCount => widget.initial == null ? 9 : 8;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      final p = init.primary;
      _age = p.age;
      _sex = p.sex;
      _heightCm = p.heightCm;
      _weightKg = p.weightKg;
      _activity = p.activity;
      _goal = p.goal;
      _diet = init.diet;
      _others = init.members.where((m) => !m.isPrimary).toList();
      _liked = {...init.liked};
      _disliked = {...init.disliked};
      _allergens = {...init.allergens};
      _includeSnacks = init.includeSnacks;
      _dayRules = [...init.dayRules];
      _shopping = init.shopping;
    } else {
      _age = 28;
      _sex = Sex.male;
      _heightCm = 170;
      _weightKg = 68;
      _activity = ActivityLevel.light;
      _goal = Goal.maintain;
      _diet = DietType.veg;
      _others = [];
      _liked = {};
      _disliked = {};
      _allergens = {};
      _includeSnacks = true;
      _dayRules = [];
      _shopping = ShoppingRhythm.twice;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_page == 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    final primary = HouseholdMember(
      id: widget.initial?.primary.id ?? 'primary',
      name: 'You',
      age: _age,
      sex: _sex,
      weightKg: _weightKg,
      heightCm: _heightCm,
      activity: _activity,
      goal: _goal,
      isPrimary: true,
    );
    widget.onComplete(
      Profile(
        members: [primary, ..._others],
        diet: _diet,
        liked: _liked,
        disliked: _disliked,
        allergens: _allergens,
        includeSnacks: _includeSnacks,
        dayRules: _rulesFor(_diet),
        shopping: _shopping,
      ),
    );
  }

  /// Rules trimmed to what can matter on [diet] — "no meat on Tuesday" means
  /// nothing to a vegetarian household — and to people still in it.
  List<DayRule> _rulesFor(DietType diet) {
    final ids = {
      widget.initial?.primary.id ?? 'primary',
      ..._others.map((m) => m.id),
    };
    return [
      for (final r in _dayRules)
        r.forDiet(diet).copyWith(memberIds: r.memberIds.intersection(ids)),
    ].where((r) => !r.isEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      if (widget.initial == null) _welcomePage(),
      _aboutYouPage(),
      _activityPage(),
      _goalPage(),
      _householdPage(),
      _dietPage(),
      _preferencesPage(),
      _observancePage(),
      _shoppingPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: _page == 0
            ? (widget.initial != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null)
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(widget.initial == null ? 'Set up' : 'Edit profile'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_page + 1) / _pageCount,
            minHeight: 4,
          ),
        ),
      ),
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _page = i),
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton(
          onPressed: _next,
          child: Text(_page >= _pageCount - 1 ? 'Create my plan' : 'Continue'),
        ),
      ),
    );
  }

  Widget _scroll({required String title, String? subtitle, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }

  Widget _welcomePage() => _scroll(
        title: 'Plan your week, eat properly',
        subtitle:
            'Tell us about your household and what you like to eat. We will '
            'build a full week of meals and one shopping list to match — '
            'balancing protein and other nutrients across the whole week, not '
            'just meal by meal.',
        children: [
          _infoCard(
            icon: Icons.insights_outlined,
            title: 'Built on ICMR-NIN 2020',
            body: 'Targets follow the Indian Council of Medical Research '
                'recommended intakes, including the higher protein requirement '
                'for vegetarian, cereal-based diets.',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.wifi_off_outlined,
            title: 'Works entirely offline',
            body: 'Everything stays on your phone. No account, no sign-in, and '
                'nothing is sent anywhere.',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.medical_information_outlined,
            title: 'Not medical advice',
            body: 'This is general nutrition guidance. If you are pregnant or '
                'managing a condition such as diabetes, kidney disease or a '
                'thyroid disorder, please follow your doctor or dietitian '
                'instead.',
          ),
        ],
      );

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutYouPage() => _scroll(
        title: 'About you',
        subtitle: 'We use this to work out how much energy and protein you need '
            'each day.',
        children: [
          const SectionHeader('Sex'),
          SegmentedButton<Sex>(
            segments: const [
              ButtonSegment(value: Sex.male, label: Text('Male')),
              ButtonSegment(value: Sex.female, label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SectionHeader('Age'),
          _numberSlider(
            value: _age.toDouble(),
            min: 13,
            max: 90,
            unit: 'years',
            onChanged: (v) => setState(() => _age = v.round()),
          ),
          const SectionHeader('Height'),
          _numberSlider(
            value: _heightCm,
            min: 130,
            max: 200,
            unit: 'cm',
            onChanged: (v) => setState(() => _heightCm = v.roundToDouble()),
          ),
          const SectionHeader('Weight'),
          _numberSlider(
            value: _weightKg,
            min: 30,
            max: 150,
            unit: 'kg',
            onChanged: (v) => setState(() => _weightKg = v.roundToDouble()),
          ),
        ],
      );

  Widget _numberSlider({
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text('${value.round()} $unit',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _activityPage() => _scroll(
        title: 'How active are you?',
        subtitle: 'Be honest rather than aspirational — this scales your whole '
            'calorie target.',
        children: [
          for (final a in ActivityLevel.values)
            _choiceTile<ActivityLevel>(
              value: a,
              group: _activity,
              title: a.label,
              subtitle: a.description,
              onTap: () => setState(() => _activity = a),
            ),
        ],
      );

  Widget _goalPage() => _scroll(
        title: 'What is your goal?',
        subtitle: 'This shifts your calorie target and, importantly, how much '
            'protein we plan for.',
        children: [
          _choiceTile<Goal>(
            value: Goal.lose,
            group: _goal,
            title: 'Lose weight',
            subtitle: 'A moderate deficit, with protein kept high to protect '
                'muscle.',
            onTap: () => setState(() => _goal = Goal.lose),
          ),
          _choiceTile<Goal>(
            value: Goal.maintain,
            group: _goal,
            title: 'Stay healthy',
            subtitle: 'Maintain your weight and hit your nutrient targets.',
            onTap: () => setState(() => _goal = Goal.maintain),
          ),
          _choiceTile<Goal>(
            value: Goal.gain,
            group: _goal,
            title: 'Build muscle',
            subtitle: 'A small surplus with a noticeably higher protein target.',
            onTap: () => setState(() => _goal = Goal.gain),
          ),
        ],
      );

  Widget _householdPage() {
    final scheme = Theme.of(context).colorScheme;
    return _scroll(
      title: 'Who else eats at home?',
      subtitle: 'Meals are cooked once for everyone, so we size every recipe '
          'and the shopping list for the whole household.',
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: const Icon(Icons.person),
            ),
            title: const Text('You'),
            subtitle: Text('$_age years · ${_sex.name}'),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _others.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(_others[i].isChild
                      ? Icons.child_care
                      : Icons.person_outline),
                ),
                title: Text(_others[i].name),
                subtitle: Text(
                    '${_others[i].age} years · ${_others[i].sex.name} · '
                    '${_others[i].weightKg.round()} kg'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() {
                    final gone = _others.removeAt(i).id;
                    _dayRules = [
                      for (final r in _dayRules)
                        r.copyWith(memberIds: {...r.memberIds}..remove(gone)),
                    ].where((r) => !r.isEmpty).toList();
                  }),
                ),
                onTap: () => _editMember(i),
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _addMember,
          icon: const Icon(Icons.add),
          label: const Text('Add a family member'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Cooking for ${_others.length + 1} '
          '${_others.isEmpty ? 'person' : 'people'}.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _addMember() async {
    final result = await showModalBottomSheet<HouseholdMember>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberSheet(index: _others.length),
    );
    if (result != null) setState(() => _others.add(result));
  }

  Future<void> _editMember(int i) async {
    final result = await showModalBottomSheet<HouseholdMember>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberSheet(index: i, existing: _others[i]),
    );
    if (result != null) setState(() => _others[i] = result);
  }

  Widget _dietPage() => _scroll(
        title: 'What do you eat?',
        subtitle: 'We only ever plan meals that fit this setting.',
        children: [
          _choiceTile<DietType>(
            value: DietType.veg,
            group: _diet,
            title: 'Vegetarian',
            subtitle: 'No egg, no meat. Your protein target is raised to '
                '1 g/kg, as ICMR-NIN recommends for cereal-based diets.',
            onTap: () => setState(() => _diet = DietType.veg),
          ),
          _choiceTile<DietType>(
            value: DietType.egg,
            group: _diet,
            title: 'Eggetarian',
            subtitle: 'Vegetarian plus eggs.',
            onTap: () => setState(() => _diet = DietType.egg),
          ),
          _choiceTile<DietType>(
            value: DietType.nonveg,
            group: _diet,
            title: 'Non-vegetarian',
            subtitle: 'Everything, including chicken and fish.',
            onTap: () => setState(() => _diet = DietType.nonveg),
          ),
          const SectionHeader('Snacks'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeSnacks,
            onChanged: (v) => setState(() => _includeSnacks = v),
            title: const Text('Include an afternoon snack'),
            subtitle: const Text('A good place to add protein between meals.'),
          ),
        ],
      );

  Widget _preferencesPage() {
    final matches =
        _avoidable().where((i) => matchesSearch(i, _prefQuery)).toList();
    final groupMatches = AvoidGroup.values
        .where((g) => g.relevantTo(_diet) && _groupFoods(g).isNotEmpty)
        .where((g) => g.matchesSearch(_prefQuery))
        .toList();
    final marked = [
      if (_liked.isNotEmpty)
        '${_liked.length} favourite${_liked.length == 1 ? '' : 's'}',
      if (_disliked.isNotEmpty) '${_disliked.length} avoided',
      if (_allergens.isNotEmpty)
        '${_allergens.length} allerg${_allergens.length == 1 ? 'y' : 'ies'}',
    ];

    return _scroll(
      title: 'Anything you avoid?',
      subtitle: 'Tap once to mark a favourite, twice to avoid it, three times '
          'to clear. Long-press to mark a true allergy, which is excluded '
          'absolutely. A group, like Dairy, marks every food in it at once.',
      children: [
        FoodSearchField(
          hint: _diet == DietType.nonveg
              ? 'Search foods or groups — e.g. dairy, spinach, chicken'
              : 'Search foods or groups — e.g. dairy, spinach, paneer',
          onChanged: (q) => setState(() => _prefQuery = q),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty && groupMatches.isEmpty)
          NoSearchMatches(_prefQuery)
        else ...[
          if (groupMatches.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final g in groupMatches) _prefGroupChip(g)],
            ),
            if (matches.isNotEmpty) const Divider(height: 24),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final ing in matches) _prefChip(ing)],
          ),
        ],
        if (marked.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Marked so far: ${marked.join(', ')}.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_allergens.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Never planned: '
                      '${_allergens.map((id) => widget.ingredients[id]?.name ?? id).join(', ')}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<({String id, String name})> get _people => [
        (id: widget.initial?.primary.id ?? 'primary', name: 'You'),
        for (final m in _others) (id: m.id, name: m.name),
      ];

  Widget _observancePage() {
    final scheme = Theme.of(context).colorScheme;
    final names = {for (final p in _people) p.id: p.name};
    return _scroll(
      title: 'Any days you avoid certain foods?',
      subtitle: '${switch (_diet) {
            DietType.nonveg => 'Many families give up meat on a Tuesday, '
                'or onion and garlic on a fast day.',
            DietType.egg => 'Many families give up eggs on a Tuesday, '
                'or onion and garlic on a fast day.',
            DietType.veg => 'Many families give up onion and garlic on a '
                'fast day, or grains and dal during a vrat.',
          }} Tell us which days, and those days\' meals leave '
          'the food out. Meals are cooked once for everyone, so the whole '
          'table follows the day.',
      children: [
        for (var i = 0; i < _dayRules.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.tertiaryContainer,
                  child: Icon(
                    Icons.event_repeat,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                title: Text(describeDays(_dayRules[i].weekdays)),
                subtitle: Text(
                  '${describeAvoided(_dayRules[i], widget.ingredients, _diet)}\n'
                  'For ${_dayRules[i].memberIds.map((id) => names[id] ?? 'someone').join(', ')}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _dayRules.removeAt(i)),
                ),
                onTap: () => _editRule(i),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _editRule(null),
          icon: const Icon(Icons.add),
          label: const Text('Add a day'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _dayRules.isEmpty
              ? 'Nothing like this in your home? Just continue.'
              : 'These are kept every week, with no exceptions — unlike foods '
                  'you simply prefer to avoid.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  Future<void> _editRule(int? i) async {
    final result = await showModalBottomSheet<DayRule>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DayRuleSheet(
        people: _people,
        diet: _diet,
        ingredients: _avoidable(),
        allFoods: widget.ingredients.values
            .where((i) => _diet.admits(i.diet))
            .toList(),
        existing: i == null ? null : _dayRules[i],
      ),
    );
    if (result == null) return;
    setState(() {
      if (i == null) {
        _dayRules.add(result);
      } else {
        _dayRules[i] = result;
      }
    });
  }

  Widget _shoppingPage() => _scroll(
        title: 'How often do you shop for fresh food?',
        subtitle: 'Greens, paneer and curd only keep a few days. We plan each '
            'day\'s meals around what will still be fresh, and split the '
            'shopping list into your shopping days so nothing goes off in '
            'the fridge.',
        children: [
          for (final r in ShoppingRhythm.values)
            _choiceTile<ShoppingRhythm>(
              value: r,
              group: _shopping,
              title: r.label,
              subtitle: r.description,
              onTap: () => setState(() => _shopping = r),
            ),
          const SizedBox(height: 8),
          Text(
            'Milk is assumed to come fresh every day, as it does in most '
            'Indian homes.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  /// Ingredients a household would actually have an opinion about.
  List<Ingredient> _avoidable() => widget.ingredients.values
      .where((i) => !i.pantryStaple && _diet.admits(i.diet))
      .where(
        (i) => const {
          Aisle.vegetables,
          Aisle.pulses,
          Aisle.dairy,
          Aisle.eggmeat,
          Aisle.nuts,
          Aisle.fruits,
        }.contains(i.aisle),
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  /// Every food a group covers that this household could be served —
  /// staples like atta included, which have no chip of their own.
  Set<String> _groupFoods(AvoidGroup g) => {
        for (final i in widget.ingredients.values)
          if (_diet.admits(i.diet) && g.covers(i)) i.id,
      };

  /// A group marks all its foods at once: tap to avoid them all (or clear
  /// them), long-press for an allergy to all of them.
  Widget _prefGroupChip(AvoidGroup g) {
    final scheme = Theme.of(context).colorScheme;
    final ids = _groupFoods(g);
    final allergic = _allergens.containsAll(ids);
    final avoided = !allergic && _disliked.union(_allergens).containsAll(ids);

    final bg = allergic
        ? scheme.errorContainer
        : (avoided ? scheme.surfaceContainerHighest : null);
    final fg = allergic
        ? scheme.onErrorContainer
        : (avoided ? scheme.onSurfaceVariant : null);

    return Tooltip(
      message: g.description,
      child: GestureDetector(
        onLongPress: () => setState(() {
          if (allergic) {
            _allergens.removeAll(ids);
          } else {
            _liked.removeAll(ids);
            _disliked.removeAll(ids);
            _allergens.addAll(ids);
          }
        }),
        child: FilterChip(
          selected: avoided || allergic,
          showCheckmark: false,
          avatar: Icon(
            allergic
                ? Icons.block
                : (avoided
                    ? Icons.thumb_down_alt_outlined
                    : Icons.category_outlined),
            size: 16,
            color: fg,
          ),
          backgroundColor: bg,
          selectedColor: bg,
          label: Text(g.label, style: fg == null ? null : TextStyle(color: fg)),
          onSelected: (_) => setState(() {
            if (allergic) return; // cleared only by long-press
            if (avoided) {
              _disliked.removeAll(ids);
            } else {
              _liked.removeAll(ids);
              _disliked.addAll(ids.difference(_allergens));
            }
          }),
        ),
      ),
    );
  }

  Widget _prefChip(Ingredient ing) {
    final scheme = Theme.of(context).colorScheme;
    final liked = _liked.contains(ing.id);
    final disliked = _disliked.contains(ing.id);
    final allergic = _allergens.contains(ing.id);

    Color? bg;
    Color? fg;
    IconData? icon;
    if (allergic) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      icon = Icons.block;
    } else if (liked) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      icon = Icons.favorite;
    } else if (disliked) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.thumb_down_alt_outlined;
    }

    return GestureDetector(
      onLongPress: () => setState(() {
        _liked.remove(ing.id);
        _disliked.remove(ing.id);
        if (!_allergens.remove(ing.id)) _allergens.add(ing.id);
      }),
      child: FilterChip(
        selected: liked || disliked || allergic,
        showCheckmark: false,
        avatar: icon == null ? null : Icon(icon, size: 16, color: fg),
        backgroundColor: bg,
        selectedColor: bg,
        label: Text(ing.name, style: fg == null ? null : TextStyle(color: fg)),
        onSelected: (_) => setState(() {
          if (allergic) return; // cleared only by long-press
          if (liked) {
            _liked.remove(ing.id);
            _disliked.add(ing.id);
          } else if (disliked) {
            _disliked.remove(ing.id);
          } else {
            _liked.add(ing.id);
          }
        }),
      ),
    );
  }

  Widget _choiceTile<T>({
    required T value,
    required T group,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final selected = value == group;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for adding or editing a household member.
class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.index, this.existing});
  final int index;
  final HouseholdMember? existing;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late final TextEditingController _name;
  late int _age;
  late Sex _sex;
  double? _weight;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _age = e?.age ?? 30;
    _sex = e?.sex ?? Sex.female;
    _weight = e?.weightKg;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Default body size follows age and sex until the user overrides it.
    final ref = referenceBodyFor(_age, _sex);
    final weight = _weight ?? ref.kg;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'Add a person' : 'Edit person',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Amma, Rohan',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<Sex>(
            segments: const [
              ButtonSegment(value: Sex.male, label: Text('Male')),
              ButtonSegment(value: Sex.female, label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 16),
          Text('Age: $_age years'),
          Slider(
            value: _age.toDouble(),
            min: 1,
            max: 90,
            divisions: 89,
            onChanged: (v) => setState(() {
              _age = v.round();
              _weight = null; // fall back to the age-appropriate reference
            }),
          ),
          Text('Weight: ${weight.round()} kg'
              '${_weight == null ? '  (typical for this age)' : ''}'),
          Slider(
            value: weight.clamp(8, 150),
            min: 8,
            max: 150,
            divisions: 142,
            onChanged: (v) => setState(() => _weight = v.roundToDouble()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              final base = HouseholdMember.reference(
                id: widget.existing?.id ?? 'm${widget.index}_$_age$_sex',
                name: name.isEmpty ? 'Family member' : name,
                age: _age,
                sex: _sex,
              );
              Navigator.of(context).pop(
                _weight == null ? base : base.copyWith(weightKg: _weight),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for adding or editing a weekly observance.
class _DayRuleSheet extends StatefulWidget {
  const _DayRuleSheet({
    required this.people,
    required this.diet,
    required this.ingredients,
    required this.allFoods,
    this.existing,
  });

  final List<({String id, String name})> people;
  final DietType diet;

  /// Foods offered one by one.
  final List<Ingredient> ingredients;

  /// Everything the household might eat, which is what a group covers —
  /// staples like atta included.
  final List<Ingredient> allFoods;
  final DayRule? existing;

  @override
  State<_DayRuleSheet> createState() => _DayRuleSheetState();
}

class _DayRuleSheetState extends State<_DayRuleSheet> {
  late Set<String> _members;
  late Set<int> _days;
  late Set<AvoidGroup> _groups;
  late Set<String> _foods;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _members = {...?e?.memberIds};
    if (_members.isEmpty && widget.people.length == 1) {
      _members.add(widget.people.single.id);
    }
    _days = {...?e?.weekdays};
    _groups = {...?e?.groups};
    _foods = {...?e?.ingredients};
  }

  String _nameOf(String id) =>
      widget.allFoods.where((i) => i.id == id).firstOrNull?.name ?? id;

  /// A group, ticked or not. One already covered by a wider group ticked
  /// alongside it — Chicken once All non-veg is on — shows as ticked and
  /// locked.
  Widget _groupTile(AvoidGroup g) {
    final implied = g.isImpliedBy(_groups, widget.allFoods);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: implied || _groups.contains(g),
      onChanged: implied
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _groups.add(g);
                  // Drop what the new group now covers: narrower groups, and
                  // foods picked one by one.
                  _groups.removeWhere(
                      (o) => o.isImpliedBy({..._groups}..remove(o), widget.allFoods));
                  _foods.removeWhere((id) => widget.allFoods
                      .any((i) => i.id == id && g.covers(i)));
                } else {
                  _groups.remove(g);
                }
              }),
      title: Text(g.label, style: const TextStyle(fontSize: 15)),
      subtitle: Text(g.description),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  DayRule get _rule => DayRule(
        memberIds: _members,
        weekdays: _days,
        groups: _groups,
        ingredients: _foods,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = AvoidGroup.values
        .where((g) => g.relevantTo(widget.diet))
        .where((g) => widget.allFoods.any(g.covers))
        .toList();

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      // Save stays pinned below the list, however long the food list gets.
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              children: [
                Text(
                  widget.existing == null ? 'Add a day' : 'Edit day',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.people.length > 1) ...[
                  label('Who keeps it?'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in widget.people)
                        FilterChip(
                          label: Text(p.name),
                          selected: _members.contains(p.id),
                          onSelected: (v) => setState(
                            () =>
                                v ? _members.add(p.id) : _members.remove(p.id),
                          ),
                        ),
                    ],
                  ),
                ],
                label('Which days?'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 0; d < 7; d++)
                      FilterChip(
                        label: Text(weekdayNames[d].substring(0, 3)),
                        selected: _days.contains(d),
                        onSelected: (v) =>
                            setState(() => v ? _days.add(d) : _days.remove(d)),
                      ),
                  ],
                ),
                label('What is left out?'),
                if (_foods.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in _foods)
                        InputChip(
                          label: Text(
                            _nameOf(id),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          selected: true,
                          showCheckmark: false,
                          onDeleted: () => setState(() => _foods.remove(id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                FoodSearchField(
                  hint: widget.diet == DietType.nonveg
                      ? 'Search foods or groups — e.g. dairy, meat, paneer'
                      : 'Search foods or groups — e.g. dairy, dal, paneer',
                  onChanged: (q) => setState(() => _query = q),
                ),
                const SizedBox(height: 4),
                () {
                  // Ticked groups stay on screen whatever the search, so they
                  // can always be unticked.
                  final shownGroups = groups
                      .where((g) =>
                          _groups.contains(g) || g.matchesSearch(_query))
                      .toList();
                  final matches = widget.ingredients
                      .where((i) => !_foods.contains(i.id))
                      .where((i) => !_groups.any((g) => g.covers(i)))
                      .where((i) => matchesSearch(i, _query))
                      .toList();
                  if (shownGroups.isEmpty && matches.isEmpty) {
                    return NoSearchMatches(_query);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final g in shownGroups) _groupTile(g),
                      if (matches.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final ing in matches)
                              FilterChip(
                                label: Text(
                                  ing.name,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                selected: false,
                                onSelected: (_) =>
                                    setState(() => _foods.add(ing.id)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                }(),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_rule.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Pick ${_members.isEmpty ? 'who, ' : ''}'
                      '${_days.isEmpty ? 'at least one day, ' : ''}'
                      'and what is left out.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _rule.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_rule),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
