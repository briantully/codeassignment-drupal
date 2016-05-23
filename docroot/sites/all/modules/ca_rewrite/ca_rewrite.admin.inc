<?php

/**
 * Generates the ca_rewrite_pattern editing form.
 */
function ca_rewrite_pattern_form($form, &$form_state, $ca_rewrite_pattern, $op = 'edit') {
  $form['description'] = array(
    '#type' => 'textfield',
    '#title' => t('Description'),
    '#default_value' => $ca_rewrite_pattern->description,
  );
  $form['pattern'] = array(
    '#type' => 'textfield',
    '#title' => t('Pattern'),
    '#default_value' => $ca_rewrite_pattern->pattern,
  );
  $form['replacement'] = array(
    '#type' => 'textfield',
    '#title' => t('Replacement'),
    '#default_value' => $ca_rewrite_pattern->replacement,
  );
  $form['actions'] = array('#type' => 'actions');
  $form['actions']['submit'] = array(
    '#type' => 'submit',
    '#value' => t('Save Pattern'),
    '#weight' => 40,
  );
  return $form;
}

/**
 * Form API submit callback for the type form.
 */
function ca_rewrite_pattern_form_submit(&$form, &$form_state) {
  $ca_rewrite_pattern = entity_ui_form_submit_build_entity($form, $form_state);
  // Save and go back.
  $ca_rewrite_pattern->save();
  $form_state['redirect'] = CA_REWRITE_URI_PATH;
}
