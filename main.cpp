#include <QApplication>
#include <QMainWindow>
#include <QWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QPushButton>
#include <QTextEdit>
#include <QLabel>
#include <QProgressBar>
#include <QCheckBox>
#include <QProcess>
#include <QFileDialog>
#include <QMessageBox>
#include <QScrollBar>
#include <QGroupBox>
#include <QFont>

class Qt6InstallerGUI : public QMainWindow
{
    Q_OBJECT

public:
    Qt6InstallerGUI(QWidget *parent = nullptr) : QMainWindow(parent)
    {
        setupUI();
        setupProcess();
    }

    ~Qt6InstallerGUI()
    {
        if (process && process->state() != QProcess::NotRunning) {
            process->kill();
            process->waitForFinished();
        }
    }

private slots:
    void selectScriptPath()
    {
        QString fileName = QFileDialog::getOpenFileName(
            this,
            tr("Select install.sh"),
            QDir::homePath(),
            tr("Shell Scripts (*.sh);;All Files (*)")
        );
        
        if (!fileName.isEmpty()) {
            scriptPath = fileName;
            scriptPathLabel->setText(QString("<b>Script:</b> %1").arg(scriptPath));
            startButton->setEnabled(true);
        }
    }

    void startInstallation()
    {
        if (scriptPath.isEmpty()) {
            QMessageBox::warning(this, "No Script", "Please select install.sh first!");
            return;
        }

        // Disable controls
        startButton->setEnabled(false);
        stopButton->setEnabled(true);
        browseButton->setEnabled(false);
        qmlCheckbox->setEnabled(false);

        // Clear output
        outputText->clear();
        appendOutput("=== Starting Qt6 Installation ===\n", Qt::blue);
        appendOutput(QString("Script: %1\n").arg(scriptPath), Qt::darkGray);
        appendOutput(QString("QML Support: %1\n\n").arg(qmlCheckbox->isChecked() ? "Yes" : "No"), Qt::darkGray);

        // Prepare process
        QStringList arguments;
        arguments << scriptPath;

        // Set environment variable for QML choice
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("BUILD_QML", qmlCheckbox->isChecked() ? "y" : "n");
        process->setProcessEnvironment(env);

        // Start process
        process->start("/bin/bash", arguments);
        
        if (!process->waitForStarted()) {
            appendOutput("ERROR: Failed to start installation process!\n", Qt::red);
            resetUI();
        }
    }

    void stopInstallation()
    {
        if (process && process->state() != QProcess::NotRunning) {
            appendOutput("\n=== Stopping installation... ===\n", Qt::red);
            process->kill();
            process->waitForFinished();
            appendOutput("Installation stopped by user.\n", Qt::red);
        }
        resetUI();
    }

    void handleStdout()
    {
        QByteArray data = process->readAllStandardOutput();
        QString output = QString::fromUtf8(data);
        
        // Parse and color-code output
        QStringList lines = output.split('\n');
        for (const QString &line : lines) {
            if (line.isEmpty()) continue;
            
            QColor color = Qt::black;
            
            if (line.contains("[INFO]") || line.contains("Building") || line.contains("Configuring")) {
                color = Qt::blue;
            } else if (line.contains("[SUCCESS]") || line.contains("successfully") || line.contains("Complete")) {
                color = Qt::darkGreen;
            } else if (line.contains("[WARNING]")) {
                color = QColor(255, 140, 0); // Orange
            } else if (line.contains("[ERROR]") || line.contains("error:") || line.contains("Error")) {
                color = Qt::red;
            } else if (line.contains("===")) {
                color = Qt::darkCyan;
            }
            
            appendOutput(line + "\n", color);
        }
        
        // Update progress (simple heuristic)
        updateProgress(output);
    }

    void handleStderr()
    {
        QByteArray data = process->readAllStandardError();
        QString output = QString::fromUtf8(data);
        appendOutput(output, QColor(200, 0, 0)); // Dark red for errors
    }

    void processFinished(int exitCode, QProcess::ExitStatus exitStatus)
    {
        if (exitStatus == QProcess::CrashExit) {
            appendOutput("\n=== Process crashed ===\n", Qt::red);
        } else if (exitCode == 0) {
            appendOutput("\n=== Installation completed successfully! ===\n", Qt::darkGreen);
            progressBar->setValue(100);
            QMessageBox::information(this, "Success", "Qt6 installation completed successfully!");
        } else {
            appendOutput(QString("\n=== Installation failed with exit code %1 ===\n").arg(exitCode), Qt::red);
            QMessageBox::critical(this, "Installation Failed", 
                QString("Installation failed with exit code %1\nCheck the output for details.").arg(exitCode));
        }
        
        resetUI();
    }

private:
    void setupUI()
    {
        setWindowTitle("Qt6 Cross-Compilation Installer for macOS");
        resize(900, 700);

        QWidget *centralWidget = new QWidget(this);
        QVBoxLayout *mainLayout = new QVBoxLayout(centralWidget);

        // Header
        QLabel *titleLabel = new QLabel("Qt6 Cross-Compilation Setup");
        QFont titleFont = titleLabel->font();
        titleFont.setPointSize(18);
        titleFont.setBold(true);
        titleLabel->setFont(titleFont);
        titleLabel->setAlignment(Qt::AlignCenter);
        mainLayout->addWidget(titleLabel);

        QLabel *subtitleLabel = new QLabel("Build Qt6 for macOS and Windows ARM64");
        subtitleLabel->setAlignment(Qt::AlignCenter);
        subtitleLabel->setStyleSheet("color: #666; font-size: 12px;");
        mainLayout->addWidget(subtitleLabel);

        mainLayout->addSpacing(10);

        // Script selection group
        QGroupBox *scriptGroup = new QGroupBox("Installation Script");
        QHBoxLayout *scriptLayout = new QHBoxLayout(scriptGroup);
        
        scriptPathLabel = new QLabel("<b>Script:</b> Not selected");
        scriptLayout->addWidget(scriptPathLabel);
        
        browseButton = new QPushButton("Browse...");
        browseButton->setMaximumWidth(100);
        connect(browseButton, &QPushButton::clicked, this, &Qt6InstallerGUI::selectScriptPath);
        scriptLayout->addWidget(browseButton);
        
        mainLayout->addWidget(scriptGroup);

        // Options group
        QGroupBox *optionsGroup = new QGroupBox("Build Options");
        QVBoxLayout *optionsLayout = new QVBoxLayout(optionsGroup);
        
        qmlCheckbox = new QCheckBox("Build with QML/QtQuick support (adds 1-2 hours)");
        qmlCheckbox->setChecked(false);
        optionsLayout->addWidget(qmlCheckbox);
        
        mainLayout->addWidget(optionsGroup);

        // Control buttons
        QHBoxLayout *buttonLayout = new QHBoxLayout();
        
        startButton = new QPushButton("Start Installation");
        startButton->setEnabled(false);
        startButton->setStyleSheet("QPushButton { background-color: #4CAF50; color: white; padding: 8px; font-weight: bold; } QPushButton:hover { background-color: #45a049; } QPushButton:disabled { background-color: #cccccc; }");
        connect(startButton, &QPushButton::clicked, this, &Qt6InstallerGUI::startInstallation);
        buttonLayout->addWidget(startButton);

        stopButton = new QPushButton("Stop");
        stopButton->setEnabled(false);
        stopButton->setStyleSheet("QPushButton { background-color: #f44336; color: white; padding: 8px; font-weight: bold; } QPushButton:hover { background-color: #da190b; }");
        connect(stopButton, &QPushButton::clicked, this, &Qt6InstallerGUI::stopInstallation);
        buttonLayout->addWidget(stopButton);

        mainLayout->addLayout(buttonLayout);

        // Progress bar
        progressBar = new QProgressBar();
        progressBar->setMinimum(0);
        progressBar->setMaximum(100);
        progressBar->setValue(0);
        progressBar->setTextVisible(true);
        mainLayout->addWidget(progressBar);

        // Output text area
        QLabel *outputLabel = new QLabel("Installation Output:");
        outputLabel->setStyleSheet("font-weight: bold;");
        mainLayout->addWidget(outputLabel);

        outputText = new QTextEdit();
        outputText->setReadOnly(true);
        outputText->setFont(QFont("Monaco", 11));
        outputText->setStyleSheet("QTextEdit { background-color: #1e1e1e; color: #d4d4d4; border: 1px solid #444; }");
        mainLayout->addWidget(outputText);

        // Status bar
        statusLabel = new QLabel("Ready to install");
        statusLabel->setStyleSheet("padding: 5px; background-color: #f0f0f0; border-top: 1px solid #ccc;");
        mainLayout->addWidget(statusLabel);

        setCentralWidget(centralWidget);
    }

    void setupProcess()
    {
        process = new QProcess(this);
        connect(process, &QProcess::readyReadStandardOutput, this, &Qt6InstallerGUI::handleStdout);
        connect(process, &QProcess::readyReadStandardError, this, &Qt6InstallerGUI::handleStderr);
        connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &Qt6InstallerGUI::processFinished);
    }

    void appendOutput(const QString &text, const QColor &color)
    {
        QTextCharFormat format;
        format.setForeground(QBrush(color));
        
        QTextCursor cursor = outputText->textCursor();
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text, format);
        
        outputText->setTextCursor(cursor);
        outputText->ensureCursorVisible();
        
        // Auto-scroll
        QScrollBar *scrollBar = outputText->verticalScrollBar();
        scrollBar->setValue(scrollBar->maximum());
    }

    void updateProgress(const QString &output)
    {
        // Simple progress estimation based on output keywords
        static int currentProgress = 0;
        
        if (output.contains("Checking prerequisites")) currentProgress = 5;
        else if (output.contains("llvm-mingw")) currentProgress = 10;
        else if (output.contains("Qt6 source")) currentProgress = 15;
        else if (output.contains("Configuring Qt6 host")) currentProgress = 20;
        else if (output.contains("Building Qt6 host")) currentProgress = 30;
        else if (output.contains("Installing Qt6 host")) currentProgress = 50;
        else if (output.contains("Configuring Qt6 Windows")) currentProgress = 55;
        else if (output.contains("Building Qt6 Windows")) currentProgress = 70;
        else if (output.contains("Installing Qt6 Windows")) currentProgress = 85;
        else if (output.contains("test application")) currentProgress = 95;
        else if (output.contains("Installation Complete")) currentProgress = 100;
        
        if (currentProgress > progressBar->value()) {
            progressBar->setValue(currentProgress);
            statusLabel->setText(QString("Progress: %1%").arg(currentProgress));
        }
    }

    void resetUI()
    {
        startButton->setEnabled(true);
        stopButton->setEnabled(false);
        browseButton->setEnabled(true);
        qmlCheckbox->setEnabled(true);
        statusLabel->setText("Ready");
    }

    // UI Elements
    QPushButton *startButton;
    QPushButton *stopButton;
    QPushButton *browseButton;
    QTextEdit *outputText;
    QProgressBar *progressBar;
    QCheckBox *qmlCheckbox;
    QLabel *scriptPathLabel;
    QLabel *statusLabel;
    
    // Process
    QProcess *process;
    QString scriptPath;
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    Qt6InstallerGUI window;
    window.show();

    return app.exec();
}

#include "main.moc"
