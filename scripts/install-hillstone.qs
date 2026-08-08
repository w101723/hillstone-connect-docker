function Controller() {
    installer.autoRejectMessageBoxes();
    installer.installationFinished.connect(function() {
        gui.clickButton(buttons.NextButton);
    });
}

Controller.prototype.IntroductionPageCallback = function() {
    gui.clickButton(buttons.NextButton);
};

Controller.prototype.LicenseAgreementPageCallback = function() {
    var page = gui.currentPageWidget();
    page.AcceptLicenseRadioButton.setChecked(true);
    gui.clickButton(buttons.NextButton);
};

Controller.prototype.TargetDirectoryPageCallback = function() {
    gui.clickButton(buttons.NextButton);
};

Controller.prototype.ComponentSelectionPageCallback = function() {
    gui.clickButton(buttons.NextButton);
};

Controller.prototype.ReadyForInstallationPageCallback = function() {
    gui.clickButton(buttons.NextButton);
};

Controller.prototype.FinishedPageCallback = function() {
    var page = gui.currentPageWidget();
    if (page.RunItCheckBox) {
        page.RunItCheckBox.setChecked(false);
    }
    gui.clickButton(buttons.FinishButton);
};
